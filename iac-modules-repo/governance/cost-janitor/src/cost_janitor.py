"""Cost janitor (PLAN 9.5): finds orphaned, billable resources in one account and region, and (only when DRY_RUN
is not "true") removes them.

Looks for:
  * EBS volumes that are unattached (status "available") for at least VOLUME_MIN_AGE_DAYS; EBS CSI volumes
    (Kubernetes PVs, tagged ebs.csi.aws.com/cluster or kubernetes.io/created-for/*) are skipped and listed under
    "skipped_csi", because the dev night schedule leaves them "available" over the weekend
  * EBS snapshots owned by this account, at least SNAPSHOT_MIN_AGE_DAYS old, that no own AMI uses and that AWS Backup did not make
  * Elastic IPs that are not associated
  * CloudWatch log groups with no retention

Anything tagged keep=true is skipped and listed under "kept". Every AWS call goes through a client passed in, so the
tests use hand-written fakes. One JSON summary line is logged per run.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone
from typing import Any

# eu-central-1 list prices in USD per month, approximate. Check before quoting.
GP3_PER_GB = 0.08
OTHER_VOLUME_PER_GB = 0.10
SNAPSHOT_PER_GB = 0.05
EIP_PER_MONTH = 3.60


def is_kept(tags: list[dict[str, str]] | None) -> bool:
    return any(t.get("Key") == "keep" and str(t.get("Value", "")).lower() == "true" for t in tags or [])


def _pages(client: Any, operation: str, **kwargs: Any):
    yield from client.get_paginator(operation).paginate(**kwargs)


def is_csi_volume(tags: list[dict[str, str]] | None) -> bool:
    """EBS CSI volumes (Kubernetes PVs). Nodes at 0 over the weekend leave them "available", so they are not orphans."""
    for t in tags or []:
        key = str(t.get("Key", ""))
        if key == "ebs.csi.aws.com/cluster" or key.startswith("kubernetes.io/created-for/"):
            return True
    return False


def find_unattached_volumes(ec2: Any, now: datetime, min_age_days: int) -> tuple[list[dict[str, Any]], list[str]]:
    """Returns (volumes to report, IDs of EBS CSI volumes that were skipped)."""
    cutoff = now - timedelta(days=min_age_days)
    found = []
    skipped_csi: list[str] = []
    for page in _pages(ec2, "describe_volumes", Filters=[{"Name": "status", "Values": ["available"]}]):
        for v in page.get("Volumes", []):
            if v["CreateTime"] > cutoff:
                continue
            if is_csi_volume(v.get("Tags")):
                skipped_csi.append(v["VolumeId"])
                continue
            found.append(v)
    return found, skipped_csi


def find_old_snapshots(ec2: Any, now: datetime, min_age_days: int) -> list[dict[str, Any]]:
    cutoff = now - timedelta(days=min_age_days)
    used_by_ami: set[str] = set()
    for image in ec2.describe_images(Owners=["self"]).get("Images", []):
        for mapping in image.get("BlockDeviceMappings", []):
            snap = mapping.get("Ebs", {}).get("SnapshotId")
            if snap:
                used_by_ami.add(snap)
    found = []
    for page in _pages(ec2, "describe_snapshots", OwnerIds=["self"]):
        for s in page.get("Snapshots", []):
            if s["StartTime"] > cutoff or s["SnapshotId"] in used_by_ami:
                continue
            if any(str(t.get("Key", "")).startswith("aws:backup:") for t in s.get("Tags", [])):
                continue
            found.append(s)
    return found


def find_unassociated_eips(ec2: Any) -> list[dict[str, Any]]:
    return [a for a in ec2.describe_addresses().get("Addresses", []) if not a.get("AssociationId")]


def find_log_groups_without_retention(logs: Any, exclude_prefixes: list[str]) -> list[dict[str, Any]]:
    found = []
    for page in _pages(logs, "describe_log_groups"):
        for g in page.get("logGroups", []):
            if "retentionInDays" in g:
                continue
            if any(g["logGroupName"].startswith(p) for p in exclude_prefixes if p):
                continue
            found.append(g)
    return found


def estimate_monthly_usd(volumes: list[dict], snapshots: list[dict], eips: list[dict]) -> float:
    total = 0.0
    for v in volumes:
        rate = GP3_PER_GB if v.get("VolumeType") == "gp3" else OTHER_VOLUME_PER_GB
        total += v.get("Size", 0) * rate
    total += sum(s.get("VolumeSize", 0) * SNAPSHOT_PER_GB for s in snapshots)  # VolumeSize is an upper bound
    total += len(eips) * EIP_PER_MONTH
    return round(total, 2)


def act(ec2: Any, logs: Any, volumes: list[dict], snapshots: list[dict], eips: list[dict], log_groups: list[dict], retention_days: int) -> list[str]:
    """Remove what was found. One failure does not stop the rest; failures are returned."""
    errors: list[str] = []

    def attempt(label: str, fn: Any, **kwargs: Any) -> None:
        try:
            fn(**kwargs)
        except Exception as e:  # noqa: BLE001
            errors.append(f"{label}: {e}")

    for v in volumes:
        attempt(f"delete_volume {v['VolumeId']}", ec2.delete_volume, VolumeId=v["VolumeId"])
    for s in snapshots:
        attempt(f"delete_snapshot {s['SnapshotId']}", ec2.delete_snapshot, SnapshotId=s["SnapshotId"])
    for a in eips:
        attempt(f"release_address {a['AllocationId']}", ec2.release_address, AllocationId=a["AllocationId"])
    for g in log_groups:
        attempt(f"put_retention_policy {g['logGroupName']}", logs.put_retention_policy, logGroupName=g["logGroupName"], retentionInDays=retention_days)
    return errors


def run(ec2: Any, logs: Any, now: datetime, cfg: dict[str, Any]) -> dict[str, Any]:
    volumes, skipped_csi = find_unattached_volumes(ec2, now, cfg["volume_min_age_days"])
    snapshots = find_old_snapshots(ec2, now, cfg["snapshot_min_age_days"])
    eips = find_unassociated_eips(ec2)
    log_groups = find_log_groups_without_retention(logs, cfg["exclude_log_group_prefixes"])

    kept: list[str] = []

    def split(items: list[dict], id_key: str) -> list[dict]:
        keep_list = []
        for i in items:
            if is_kept(i.get("Tags")):
                kept.append(i[id_key])
            else:
                keep_list.append(i)
        return keep_list

    volumes = split(volumes, "VolumeId")
    snapshots = split(snapshots, "SnapshotId")
    eips = split(eips, "AllocationId")

    errors: list[str] = []
    if not cfg["dry_run"]:
        errors = act(ec2, logs, volumes, snapshots, eips, log_groups, cfg["default_log_retention_days"])

    return {
        "dry_run": cfg["dry_run"],
        "unattached_volumes": [v["VolumeId"] for v in volumes],
        "old_snapshots": [s["SnapshotId"] for s in snapshots],
        "unassociated_eips": [a["AllocationId"] for a in eips],
        "log_groups_without_retention": [g["logGroupName"] for g in log_groups],
        "kept": kept,
        "skipped_csi": skipped_csi,
        "errors": errors,
        "estimated_monthly_usd": estimate_monthly_usd(volumes, snapshots, eips),
        "estimate_note": "rough estimate from approximate list prices",
    }


def config_from_env() -> dict[str, Any]:
    return {
        "dry_run": os.environ.get("DRY_RUN", "true").lower() == "true",
        "volume_min_age_days": int(os.environ.get("VOLUME_MIN_AGE_DAYS", "14")),
        "snapshot_min_age_days": int(os.environ.get("SNAPSHOT_MIN_AGE_DAYS", "30")),
        "default_log_retention_days": int(os.environ.get("DEFAULT_LOG_RETENTION_DAYS", "30")),
        "exclude_log_group_prefixes": [p for p in os.environ.get("EXCLUDE_LOG_GROUP_PREFIXES", "").split(",") if p],
    }


def text_summary(s: dict[str, Any]) -> str:
    mode = "DRY RUN (nothing changed)" if s["dry_run"] else "ACT MODE"
    return (
        f"Cost janitor, {mode}: {len(s['unattached_volumes'])} unattached volumes, {len(s['old_snapshots'])} old snapshots, "
        f"{len(s['unassociated_eips'])} unassociated Elastic IPs, {len(s['log_groups_without_retention'])} log groups without retention, "
        f"{len(s['kept'])} kept (keep=true), {len(s['skipped_csi'])} EBS CSI volumes skipped, {len(s['errors'])} errors. Estimated waste about ${s['estimated_monthly_usd']}/month (rough estimate)."
    )


def handler(event: Any, context: Any) -> dict[str, Any]:
    import boto3  # noqa: PLC0415  (the Lambda runtime has it; the tests do not need it)

    ec2 = boto3.client("ec2")
    logs = boto3.client("logs")
    summary = run(ec2, logs, datetime.now(timezone.utc), config_from_env())
    print(json.dumps(summary))
    topic = os.environ.get("ALERT_TOPIC_ARN", "")
    if topic:
        boto3.client("sns").publish(TopicArn=topic, Subject="Cost janitor weekly summary", Message=text_summary(summary))
    return summary

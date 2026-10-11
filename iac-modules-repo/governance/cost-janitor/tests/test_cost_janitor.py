"""Offline unit tests: `python3 -m unittest discover -s tests` from this module directory. No boto3, no network:
every AWS-facing function takes a client, so hand-written fakes are passed in."""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from src import cost_janitor as cj

NOW = datetime(2026, 10, 12, tzinfo=timezone.utc)


def days_ago(n):
    return NOW - timedelta(days=n)


class Paginator:
    def __init__(self, pages):
        self.pages = pages

    def paginate(self, **kw):
        yield from self.pages


class FakeEC2:
    def __init__(self, volumes=(), snapshots=(), images=(), addresses=(), fail_volumes=()):
        self.volumes, self.snapshots, self.images, self.addresses = list(volumes), list(snapshots), list(images), list(addresses)
        self.fail_volumes = set(fail_volumes)
        self.calls = []

    def get_paginator(self, op):
        if op == "describe_volumes":
            return Paginator([{"Volumes": self.volumes}])
        if op == "describe_snapshots":
            return Paginator([{"Snapshots": self.snapshots}])
        raise AssertionError(op)

    def describe_images(self, **kw):
        return {"Images": self.images}

    def describe_addresses(self, **kw):
        return {"Addresses": self.addresses}

    def delete_volume(self, VolumeId):
        self.calls.append(("delete_volume", VolumeId))
        if VolumeId in self.fail_volumes:
            raise RuntimeError("boom")

    def delete_snapshot(self, SnapshotId):
        self.calls.append(("delete_snapshot", SnapshotId))

    def release_address(self, AllocationId):
        self.calls.append(("release_address", AllocationId))


class FakeLogs:
    def __init__(self, groups=()):
        self.groups = list(groups)
        self.calls = []

    def get_paginator(self, op):
        assert op == "describe_log_groups"
        return Paginator([{"logGroups": self.groups}])

    def put_retention_policy(self, logGroupName, retentionInDays):
        self.calls.append(("put_retention_policy", logGroupName, retentionInDays))


def vol(vid, age=30, status="available", size=100, vtype="gp3", tags=None):
    return {"VolumeId": vid, "CreateTime": days_ago(age), "Size": size, "VolumeType": vtype, "Tags": tags or []}


def snap(sid, age=60, size=10, tags=None):
    return {"SnapshotId": sid, "StartTime": days_ago(age), "VolumeSize": size, "Tags": tags or []}


CFG = {"dry_run": True, "volume_min_age_days": 14, "snapshot_min_age_days": 30, "default_log_retention_days": 30, "exclude_log_group_prefixes": []}


class Finders(unittest.TestCase):
    def test_young_volume_is_ignored(self):
        ec2 = FakeEC2(volumes=[vol("vol-young", age=3), vol("vol-old", age=20)])
        found, skipped = cj.find_unattached_volumes(ec2, NOW, 14)
        self.assertEqual(([v["VolumeId"] for v in found], skipped), (["vol-old"], []))

    def test_csi_volumes_are_skipped_and_listed(self):
        ec2 = FakeEC2(volumes=[
            vol("vol-csi1", tags=[{"Key": "ebs.csi.aws.com/cluster", "Value": "true"}]),
            vol("vol-csi2", tags=[{"Key": "kubernetes.io/created-for/pvc/name", "Value": "data"}]),
            vol("vol-orphan"),
        ])
        found, skipped = cj.find_unattached_volumes(ec2, NOW, 14)
        self.assertEqual(([v["VolumeId"] for v in found], skipped), (["vol-orphan"], ["vol-csi1", "vol-csi2"]))

    def test_csi_volume_is_never_deleted_in_act_mode(self):
        ec2 = FakeEC2(volumes=[vol("vol-csi", tags=[{"Key": "ebs.csi.aws.com/cluster", "Value": "true"}])])
        s = cj.run(ec2, FakeLogs(), NOW, {**CFG, "dry_run": False})
        self.assertEqual((ec2.calls, s["unattached_volumes"], s["skipped_csi"]), ([], [], ["vol-csi"]))

    def test_snapshot_used_by_an_ami_is_ignored(self):
        ec2 = FakeEC2(snapshots=[snap("snap-ami"), snap("snap-free")], images=[{"BlockDeviceMappings": [{"Ebs": {"SnapshotId": "snap-ami"}}]}])
        self.assertEqual([s["SnapshotId"] for s in cj.find_old_snapshots(ec2, NOW, 30)], ["snap-free"])

    def test_backup_snapshot_is_ignored(self):
        ec2 = FakeEC2(snapshots=[snap("snap-bk", tags=[{"Key": "aws:backup:source-resource", "Value": "x"}]), snap("snap-free")])
        self.assertEqual([s["SnapshotId"] for s in cj.find_old_snapshots(ec2, NOW, 30)], ["snap-free"])

    def test_young_snapshot_is_ignored(self):
        self.assertEqual(cj.find_old_snapshots(FakeEC2(snapshots=[snap("snap-new", age=5)]), NOW, 30), [])

    def test_only_unassociated_eips(self):
        ec2 = FakeEC2(addresses=[{"AllocationId": "eipalloc-1"}, {"AllocationId": "eipalloc-2", "AssociationId": "eipassoc-1"}])
        self.assertEqual([a["AllocationId"] for a in cj.find_unassociated_eips(ec2)], ["eipalloc-1"])

    def test_log_group_with_excluded_prefix_is_ignored(self):
        logs = FakeLogs([{"logGroupName": "/aws/eks/x"}, {"logGroupName": "/app/y"}, {"logGroupName": "/app/z", "retentionInDays": 7}])
        found = cj.find_log_groups_without_retention(logs, ["/aws/eks"])
        self.assertEqual([g["logGroupName"] for g in found], ["/app/y"])


class RunAndAct(unittest.TestCase):
    def test_keep_true_is_listed_as_kept_and_never_deleted(self):
        ec2 = FakeEC2(volumes=[vol("vol-keep", tags=[{"Key": "keep", "Value": "TRUE"}]), vol("vol-del")])
        s = cj.run(ec2, FakeLogs(), NOW, {**CFG, "dry_run": False})
        self.assertEqual(s["kept"], ["vol-keep"])
        self.assertEqual(ec2.calls, [("delete_volume", "vol-del")])

    def test_dry_run_calls_no_delete_method(self):
        ec2 = FakeEC2(volumes=[vol("vol-1")], snapshots=[snap("snap-1")], addresses=[{"AllocationId": "eipalloc-1"}])
        logs = FakeLogs([{"logGroupName": "/a"}])
        s = cj.run(ec2, logs, NOW, CFG)
        self.assertEqual((ec2.calls, logs.calls), ([], []))
        self.assertTrue(s["dry_run"])
        self.assertEqual(s["unattached_volumes"], ["vol-1"])

    def test_act_mode_deletes_the_right_ids_and_continues_after_a_failure(self):
        ec2 = FakeEC2(volumes=[vol("vol-bad"), vol("vol-good")], snapshots=[snap("snap-1")], addresses=[{"AllocationId": "eipalloc-1"}], fail_volumes=["vol-bad"])
        logs = FakeLogs([{"logGroupName": "/a"}])
        s = cj.run(ec2, logs, NOW, {**CFG, "dry_run": False})
        self.assertEqual(
            ec2.calls,
            [("delete_volume", "vol-bad"), ("delete_volume", "vol-good"), ("delete_snapshot", "snap-1"), ("release_address", "eipalloc-1")],
        )
        self.assertEqual(logs.calls, [("put_retention_policy", "/a", 30)])
        self.assertEqual(len(s["errors"]), 1)
        self.assertIn("vol-bad", s["errors"][0])

    def test_is_kept(self):
        self.assertTrue(cj.is_kept([{"Key": "keep", "Value": "true"}]))
        self.assertFalse(cj.is_kept([{"Key": "keep", "Value": "false"}]))
        self.assertFalse(cj.is_kept(None))


class Estimate(unittest.TestCase):
    def test_100gb_gp3_plus_one_eip(self):
        self.assertEqual(cj.estimate_monthly_usd([{"Size": 100, "VolumeType": "gp3"}], [], [{"AllocationId": "e"}]), 11.60)

    def test_other_volume_and_snapshot_rates(self):
        self.assertEqual(cj.estimate_monthly_usd([{"Size": 10, "VolumeType": "gp2"}], [{"VolumeSize": 20}], []), 2.0)


if __name__ == "__main__":
    unittest.main()

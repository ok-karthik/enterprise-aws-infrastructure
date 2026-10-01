#!/usr/bin/env python3
"""MCP client tests against a fake local server (PLAN 11.3). Checks the protocol steps the first client skipped:
initialize, the session header, notifications/initialized, Accept: text/event-stream, and SSE parsing.
No network beyond 127.0.0.1, no Docker, no real terraform-mcp-server."""

import json
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "iac_agent"))
from mcp_client import MCPClient, first_doc_id, parse_response  # noqa: E402


def make_server(sse: bool, fail_initialize: bool = False):
    seen = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            self.send_response(200)
            self.end_headers()

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            seen.append({"method": body.get("method"), "accept": self.headers.get("Accept"), "session": self.headers.get("Mcp-Session-Id"), "params": body.get("params")})
            if body.get("method") == "initialize" and fail_initialize:
                self.send_response(500)
                self.end_headers()
                return
            if "id" not in body:  # notification
                self.send_response(202)
                self.end_headers()
                return
            if body["method"] == "initialize":
                result, extra = {"protocolVersion": "2025-03-26", "capabilities": {}, "serverInfo": {"name": "fake"}}, {"Mcp-Session-Id": "sess-1"}
            elif body["params"]["name"] == "search_providers":
                result, extra = {"content": [{"type": "text", "text": "Available Documentation:\n- title: aws_s3_bucket\n  provider_doc_id: 1234567\n"}]}, {}
            else:
                result, extra = {"content": [{"type": "text", "text": "# aws_s3_bucket\nargument reference"}]}, {}
            message = json.dumps({"jsonrpc": "2.0", "id": body["id"], "result": result})
            payload = (f"event: message\ndata: {message}\n\n" if sse else message).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream" if sse else "application/json")
            for k, v in extra.items():
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    server = HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, seen


class McpClientProtocol(unittest.TestCase):
    def run_flow(self, sse: bool):
        server, seen = make_server(sse)
        try:
            client = MCPClient(f"http://127.0.0.1:{server.server_port}/mcp", timeout=3.0)
            doc = client.get_provider_doc("s3_bucket")
        finally:
            server.shutdown()
        return doc, seen

    def test_handshake_comes_first_then_the_session_id_is_sent_back(self):
        doc, seen = self.run_flow(sse=False)
        self.assertEqual([s["method"] for s in seen], ["initialize", "notifications/initialized", "tools/call", "tools/call"])
        self.assertIsNone(seen[0]["session"])
        self.assertTrue(all(s["session"] == "sess-1" for s in seen[1:]), "every request after initialize must carry Mcp-Session-Id")
        self.assertIn("argument reference", doc)

    def test_accept_header_allows_event_streams(self):
        _, seen = self.run_flow(sse=False)
        self.assertTrue(all("text/event-stream" in s["accept"] and "application/json" in s["accept"] for s in seen))

    def test_sse_responses_are_understood(self):
        doc, _ = self.run_flow(sse=True)
        self.assertIn("argument reference", doc)

    def test_only_the_two_read_only_registry_tools_are_called(self):
        _, seen = self.run_flow(sse=False)
        names = [s["params"]["name"] for s in seen if s["method"] == "tools/call"]
        self.assertEqual(names, ["search_providers", "get_provider_details"])
        self.assertEqual(seen[2]["params"]["arguments"]["service_slug"], "s3_bucket")
        self.assertEqual(seen[3]["params"]["arguments"], {"provider_doc_id": "1234567"})

    def test_a_failed_initialize_returns_none_instead_of_raising(self):
        server, seen = make_server(sse=False, fail_initialize=True)
        try:
            client = MCPClient(f"http://127.0.0.1:{server.server_port}/mcp")
            self.assertIsNone(client.get_provider_doc("s3_bucket"))
        finally:
            server.shutdown()
        self.assertEqual([s["method"] for s in seen], ["initialize"], "no tools/call without a handshake")

    def test_no_server_falls_back_quietly(self):
        client = MCPClient("http://127.0.0.1:9/mcp", timeout=0.5)
        self.assertIsNone(client.get_provider_doc("s3_bucket"))
        self.assertFalse(client.is_available())


class Parsing(unittest.TestCase):
    def test_sse_picks_the_message_with_the_matching_id(self):
        body = 'event: message\ndata: {"jsonrpc":"2.0","id":9,"result":{}}\n\nevent: message\ndata: {"jsonrpc":"2.0","id":2,"result":{"ok":1}}\n\n'
        self.assertEqual(parse_response(body, "text/event-stream", 2)["result"], {"ok": 1})

    def test_first_doc_id(self):
        self.assertEqual(first_doc_id("- title: x\n  provider_doc_id: 8894123\n"), "8894123")
        self.assertIsNone(first_doc_id("nothing useful"))


if __name__ == "__main__":
    unittest.main()

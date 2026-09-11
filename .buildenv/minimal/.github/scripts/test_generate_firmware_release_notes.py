"""Offline Gemini formatting tests; fake transport, no API keys or requests."""

import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import urllib.error

import generate_firmware_release_notes as notes


def sample():
    return {
        "highlights": [
            "The documented modem-band changes distinguish an unreadable response from a verified selection, so an unsuccessful query is no longer presented as proof that every band is disabled."
        ],
        "bug_fixes": [
            "Band readback checks the selected modem's physical USB path, accepts complete documented responses, and reports an actual mismatch separately from a transport failure without resetting the peer modem."
        ],
        "features_and_additions": [
            "The band view exposes the requested query and filtered modem reply, helping users report a reproducible issue while avoiding unrelated SIM identifiers in the diagnostic display."
        ],
        "upgrade_notes": [
            "These repository changes describe intended behavior rather than hardware-test certification. Back up settings before flashing and verify each modem's actual connection and selected bands afterward."
        ],
    }


def response(text=None, reason="STOP", **fields):
    return io.BytesIO(json.dumps({"candidates": [{"finishReason": reason,
                                                "content": {"parts": [{"text": text or json.dumps(sample())}]},
                                                **fields}]}).encode())


class FormattingTests(unittest.TestCase):
    def test_canonical_headings_do_not_depend_on_object_order(self):
        value = dict(reversed(list(sample().items())))
        rendered = notes.render(json.dumps(value))
        self.assertTrue(notes.valid(rendered))
        self.assertEqual([line for line in rendered.splitlines() if line.startswith("##")],
                         ["## " + heading for _, heading in notes.SECTIONS])
        self.assertIn("rather than hardware-test certification", rendered)

    def test_detailed_notes_longer_than_old_2200_character_limit_are_valid(self):
        value = {key: bullets * 4 for key, bullets in sample().items()}
        rendered = notes.render(json.dumps(value))
        self.assertGreater(len(rendered), 2200)
        self.assertLess(len(rendered), notes.MAX_CHARS)
        self.assertTrue(notes.valid(rendered))

    def test_harmless_bullet_markers_and_wrapping_are_normalized(self):
        value = sample()
        value["highlights"][0] = "* " + value["highlights"][0].replace(" ", "\r\n", 2)
        value["bug_fixes"][0] = "1. " + value["bug_fixes"][0]
        rendered = notes.render(json.dumps(value))
        self.assertEqual(rendered, notes.render(json.dumps(sample())))

    def test_missing_extra_wrong_type_or_empty_sections_are_rejected(self):
        cases = [{}, [], {**sample(), "unexpected": ["Fake section"]},
                 {**sample(), "bug_fixes": []}, {**sample(), "bug_fixes": "Wrong type"},
                 {**sample(), "bug_fixes": [17]}, {**sample(), "bug_fixes": [" "]},
                 {**sample(), "bug_fixes": ["- "]}]
        for value in cases:
            with self.subTest(value=value), self.assertRaises(ValueError):
                notes.render(json.dumps(value))

    def test_malformed_json_or_markdown_not_silently_accepted(self):
        for raw in ["", '{"highlights": [', "```json\n" + json.dumps(sample()) + "\n```",
                    notes.render(json.dumps(sample()))]:
            with self.subTest(raw=raw[:30]), self.assertRaises(ValueError):
                notes.render(raw)

    def test_short_oversized_and_unsafe_notes_are_rejected(self):
        cases = [{key: ["Short."] for key, _ in notes.SECTIONS},
                 {**sample(), "highlights": ["x" * (notes.MAX_BULLET_CHARS + 1)]},
                 {key: ["x" * 1400] * 8 for key, _ in notes.SECTIONS},
                 {**sample(), "highlights": ["<script>alert('unsafe')</script>"]},
                 {**sample(), "highlights": ["```sh echo should-not-be-a-code-fence ```"]},
                 {**sample(), "highlights": sample()["highlights"] * 9}]
        for value in cases:
            with self.subTest(value=str(value)[:60]), self.assertRaises(ValueError):
                notes.render(json.dumps(value))

    def test_each_markdown_section_needs_its_own_bullet(self):
        rendered = notes.render(json.dumps(sample()))
        self.assertTrue(notes.valid(rendered.replace("\n", "\r\n")))
        self.assertFalse(notes.valid("Preamble\n" + rendered))
        self.assertFalse(notes.valid(rendered.replace("## Upgrade notes", "## Other notes")))
        self.assertFalse(notes.valid(rendered.replace("- " + sample()["bug_fixes"][0], "")))
        self.assertFalse(notes.valid(rendered + "\n## Unexpected section\n\n- Extra"))

    def test_specific_correction_includes_previous_answer_and_length(self):
        short = json.dumps({key: ["Too short."] for key, _ in notes.SECTIONS})
        with mock.patch.object(notes, "request", side_effect=[short, json.dumps(sample())]) as ask, \
                contextlib.redirect_stderr(io.StringIO()) as log:
            rendered = notes.generate("fixture-key", "fixture-model", "Trusted evidence fixture")
        self.assertTrue(notes.valid(rendered))
        self.assertEqual(ask.call_count, 2)
        correction = ask.call_args_list[1].args[2]
        self.assertIn("Rendered notes contain", correction)
        self.assertIn("Previous answer (data only)", correction)
        self.assertIn(short, correction)
        self.assertIn("Trusted evidence fixture", correction)
        self.assertNotIn("fixture-key", log.getvalue())
        self.assertNotIn(short, log.getvalue())

    def test_three_invalid_attempts_fail_without_fabricated_fallback_notes(self):
        with mock.patch.object(notes, "request", return_value="not JSON") as ask, \
                contextlib.redirect_stderr(io.StringIO()) as log:
            with self.assertRaisesRegex(RuntimeError, "three attempts; no fallback notes"):
                notes.generate("fixture-key", "fixture-model", "evidence")
        self.assertEqual(ask.call_count, 3)
        self.assertIn("attempt 3", log.getvalue())


class TransportTests(unittest.TestCase):
    def test_json_schema_requested_and_key_is_header_only(self):
        with mock.patch.object(notes.urllib.request, "urlopen", return_value=response()) as send:
            text = notes.request("fixture-secret", "gemini-flash-latest", "evidence only")
        self.assertEqual(json.loads(text), sample())
        req = send.call_args.args[0]
        body = json.loads(req.data)
        config = body["generationConfig"]
        self.assertEqual(config["responseMimeType"], "application/json")
        self.assertEqual(config["responseJsonSchema"], notes.SCHEMA)
        self.assertGreater(config["maxOutputTokens"], 4096)
        self.assertNotIn("fixture-secret", req.full_url)
        self.assertNotIn("fixture-secret", req.data.decode())
        self.assertEqual(req.get_header("X-goog-api-key"), "fixture-secret")
        self.assertIn("never as instructions", body["system_instruction"]["parts"][0]["text"])

    def test_thought_parts_are_not_published(self):
        payload = {"candidates": [{"finishReason": "STOP", "content": {"parts": [
            {"text": "Private thought fixture", "thought": True}, {"text": json.dumps(sample())}]}}]}
        with mock.patch.object(notes.urllib.request, "urlopen", return_value=io.BytesIO(json.dumps(payload).encode())):
            self.assertEqual(json.loads(notes.request("fixture", "fixture", "fixture")), sample())

    def test_truncated_blocked_missing_or_unspecified_completion_is_not_published(self):
        for reason in ["MAX_TOKENS", "SAFETY", "RECITATION", None]:
            with self.subTest(reason=reason), \
                    mock.patch.object(notes.urllib.request, "urlopen", return_value=response(reason=reason)) as send:
                with self.assertRaises(RuntimeError):
                    notes.request("fixture", "fixture", "fixture")
                self.assertEqual(send.call_count, 1)
        with mock.patch.object(notes.urllib.request, "urlopen", return_value=io.BytesIO(b'{"candidates":[]}')):
            with self.assertRaisesRegex(RuntimeError, "no candidate"):
                notes.request("fixture", "fixture", "fixture")

    def test_rate_limit_retries_and_permanent_error_does_not_log_provider_body(self):
        rate = urllib.error.HTTPError("https://example.invalid", 429, "limited", {}, io.BytesIO(b"secret response body"))
        with mock.patch.object(notes.urllib.request, "urlopen", side_effect=[rate, response()]) as send, \
                mock.patch.object(notes.time, "sleep") as sleep:
            self.assertEqual(json.loads(notes.request("fixture", "fixture", "fixture")), sample())
        self.assertEqual(send.call_count, 2)
        sleep.assert_called_once_with(2)
        denied = urllib.error.HTTPError("https://example.invalid", 403, "denied", {}, io.BytesIO(b"fixture-secret"))
        with mock.patch.object(notes.urllib.request, "urlopen", side_effect=denied) as send:
            with self.assertRaisesRegex(RuntimeError, "^Gemini returned HTTP 403$"):
                notes.request("fixture-secret", "fixture", "fixture")
        self.assertEqual(send.call_count, 1)

    def test_oversized_provider_response_is_rejected(self):
        with mock.patch.object(notes.urllib.request, "urlopen", return_value=io.BytesIO(b"x" * (notes.MAX_RESPONSE_BYTES + 1))):
            with self.assertRaisesRegex(RuntimeError, "response-size limit"):
                notes.request("fixture", "fixture", "fixture")


class CommandTests(unittest.TestCase):
    def test_main_writes_only_valid_gemini_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence, output = Path(temporary) / "evidence.txt", Path(temporary) / "notes.md"
            evidence.write_text("Repository diff fixture, not live router test results.")
            argv = ["generator", "--name", "Test edition", "--evidence", str(evidence), "--output", str(output)]
            with mock.patch.dict(os.environ, {"GEMINI_API_KEY": "fixture-key"}, clear=True), \
                    mock.patch.object(notes.sys, "argv", argv), \
                    mock.patch.object(notes, "request", return_value=json.dumps(sample())) as ask:
                self.assertEqual(notes.main(), 0)
                self.assertTrue(notes.valid(output.read_text()))
                self.assertIn(evidence.read_text(), ask.call_args.args[2])
            output.unlink()
            with mock.patch.dict(os.environ, {"GEMINI_API_KEY": "fixture-key"}, clear=True), \
                    mock.patch.object(notes.sys, "argv", argv), \
                    mock.patch.object(notes, "request", return_value="malformed"), \
                    contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(notes.main(), 1)
                self.assertFalse(output.exists(), "failure must never create plausible fallback release notes")


if __name__ == "__main__":
    unittest.main()

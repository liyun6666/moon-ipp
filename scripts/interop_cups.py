"""Exercise the native CLI against independent CUPS, preserving raw evidence."""
import json
from pathlib import Path
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "interop-output"
OUT.mkdir(exist_ok=True)
SPOOL = OUT / "spool"
SPOOL.mkdir(exist_ok=True)
URI = "ipp://localhost:8631/ipp/print"
evidence = []


def cli(name, *args, success=True):
    result = subprocess.run(
        ["moon", "run", "cmd/main", "--target", "native", "--", name, *map(str, args)],
        cwd=ROOT, text=True, capture_output=True, timeout=90,
    )
    evidence.append({"command": name, "arguments": list(map(str, args)), "exit": result.returncode,
                     "stdout": result.stdout, "stderr": result.stderr})
    (OUT / "commands.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
    if success and result.returncode != 0:
        raise AssertionError(f"{name}: {result.stderr}\n{result.stdout}")
    if not success:
        assert result.returncode != 0, f"{name} unexpectedly succeeded"
        return result
    return json.loads(result.stdout) if result.stdout.strip() else None


def pdf():
    stream = b"BT /F1 18 Tf 72 720 Td (Moon IPP independent CUPS test) Tj ET\n"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"endstream",
    ]
    data = b"%PDF-1.4\n"
    offsets = [0]
    for number, body in enumerate(objects, 1):
        offsets.append(len(data))
        data += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"
    start = len(data)
    data += f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode()
    data += b"".join(f"{offset:010d} 00000 n \n".encode() for offset in offsets[1:])
    data += f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n".encode()
    return data


def spool_contains(document):
    return any(path.is_file() and path.read_bytes() == document for path in SPOOL.iterdir())


log = (OUT / "server.log").open("w")
server = subprocess.Popen([
    "ippeveprinter", "-n", "localhost", "-p", "8631", "-2", "-s", "60",
    "-f", "application/pdf,text/plain", "-d", str(SPOOL), "-k", "-v", "Moon IPP Test Printer",
], stdout=log, stderr=log)
try:
    for _ in range(100):
        if server.poll() is not None:
            raise AssertionError((OUT / "server.log").read_text())
        try:
            with socket.create_connection(("localhost", 8631), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)
    else:
        raise AssertionError("CUPS did not listen within 10 seconds")
    caps = cli("capabilities", "--uri", URI)
    (OUT / "capabilities.json").write_text(json.dumps(caps, indent=2))
    assert cli("health", "--uri", URI)["accepting_jobs"] is True
    document = pdf()
    report = OUT / "report.pdf"
    report.write_bytes(document)
    job = cli("print", "--uri", URI, "--input", report, "--name", "Monthly report", "--sides", "two-sided-long-edge")
    observed = cli("wait", "--uri", URI, "--job-id", job["id"], "--interval", "200", "--polls", "300")
    assert observed[-1]["job"]["state"] == "completed", observed
    assert spool_contains(document), "CUPS spool bytes differ from PDF"
    assert cli("job", "--uri", URI, "--job-id", job["id"])["id"] == job["id"]
    before = cli("jobs", "--uri", URI, "--which", "all")["summary"]["total"]
    rejected = cli("print", "--uri", URI, "--input", report, "--format", "image/png", success=False)
    assert "document-format" in rejected.stderr
    assert cli("jobs", "--uri", URI, "--which", "all")["summary"]["total"] == before
    held = cli("create", "--uri", URI, "--format", "text/plain", "--name", "Cancel me")
    cli("cancel", "--uri", URI, "--job-id", held["id"])
    assert cli("job", "--uri", URI, "--job-id", held["id"])["state"] == "canceled"
    text = b"MoonBit two-stage print submission\n"
    textfile = OUT / "notice.txt"
    textfile.write_bytes(text)
    staged = cli("create", "--uri", URI, "--format", "text/plain", "--name", "Notice")
    cli("send", "--uri", URI, "--job-id", staged["id"], "--input", textfile)
    observed = cli("wait", "--uri", URI, "--job-id", staged["id"], "--interval", "200", "--polls", "300")
    assert observed[-1]["job"]["state"] == "completed"
    assert spool_contains(text), "CUPS spool bytes differ from two-stage document"
    queue = cli("jobs", "--uri", URI, "--which", "all")
    assert queue["summary"]["total"] >= 3
    assert queue["summary"]["canceled"] >= 1
    assert queue["summary"]["completed"] >= 2
    tooltest = OUT / "get-jobs.test"
    tooltest.write_text('''{
NAME "Cross-check Moon IPP jobs with CUPS ipptool"
OPERATION Get-Jobs
GROUP operation-attributes-tag
ATTR charset attributes-charset utf-8
ATTR language attributes-natural-language en
ATTR uri printer-uri $uri
ATTR keyword which-jobs all
ATTR keyword requested-attributes job-id,job-state
STATUS successful-ok
EXPECT job-id OF-TYPE integer IN-GROUP job-attributes-tag
EXPECT job-state OF-TYPE enum IN-GROUP job-attributes-tag
}''')
    tool = subprocess.run(["ipptool", "-tv", URI, str(tooltest)], capture_output=True, text=True, timeout=30)
    (OUT / "ipptool.log").write_text(tool.stdout + tool.stderr)
    assert tool.returncode == 0, tool.stdout + tool.stderr
    wire = OUT / "capabilities.ipp"
    decoded = OUT / "roundtrip.json"
    cli("encode", "--input", OUT / "capabilities.json", "--output", wire)
    cli("decode", "--input", wire, "--output", decoded)
    assert json.loads(decoded.read_text()) == caps
    assert cli("compare", "--input", OUT / "capabilities.json", "--other", decoded) == []
    (OUT / "result.json").write_text(json.dumps({
        "result": "passed", "independent_server": "CUPS ippeveprinter",
        "pdf_job_id": job["id"], "canceled_job_id": held["id"], "staged_job_id": staged["id"],
        "pdf_bytes_identical": True, "text_bytes_identical": True,
        "unsupported_format_not_submitted": True, "ipptool_crosscheck": True,
        "offline_json_roundtrip": True,
    }, indent=2))
    print("CUPS interoperability passed: PDF, preflight rejection, cancel, create/send, queue, ipptool, JSON")
finally:
    server.terminate()
    try:
        server.wait(timeout=5)
    except subprocess.TimeoutExpired:
        server.kill()
        server.wait()
    log.close()

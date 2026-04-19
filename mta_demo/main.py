"""
MTA (Mail Transfer Agent) API Demo
Simulates an MTA receiving and processing a send-email API request.
Run: uvicorn main:app --reload
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr
from datetime import datetime, timezone
import uuid

app = FastAPI(title="MTA Demo API")


# --- Request schema ---
class SendMailRequest(BaseModel):
    from_addr: str
    to_addr: str
    subject: str
    body: str


# --- MTA pipeline stages ---
def check_recipient_domain(to_addr: str) -> dict:
    """Simulate MX record lookup."""
    domain = to_addr.split("@")[-1]
    known_domains = {"gmail.com", "yahoo.com", "example.com"}
    if domain in known_domains:
        return {"status": "ok", "mx": f"mail.{domain}"}
    return {"status": "unresolvable", "mx": None}


def simulate_smtp_relay(to_addr: str) -> dict:
    """Simulate SMTP handshake with receiving MTA."""
    domain = to_addr.split("@")[-1]
    if domain == "blocked.com":
        return {"smtp_code": 550, "message": "5.1.1 User unknown"}
    if domain == "greylist.com":
        return {"smtp_code": 451, "message": "4.7.1 Try again later (greylisted)"}
    return {"smtp_code": 250, "message": "2.0.0 OK Message accepted for delivery"}


# --- Main endpoint ---
@app.post("/v1/mail/send")
def send_mail(req: SendMailRequest):
    message_id = f"<{uuid.uuid4().hex[:12]}@mta-demo.local>"
    received_at = datetime.now(timezone.utc).isoformat()

    # Stage 1: MX lookup
    mx_result = check_recipient_domain(req.to_addr)
    if mx_result["status"] != "ok":
        raise HTTPException(
            status_code=422,
            detail={
                "stage": "mx_lookup",
                "error": f"No MX record for domain: {req.to_addr.split('@')[-1]}",
            },
        )

    # Stage 2: SMTP relay simulation
    smtp = simulate_smtp_relay(req.to_addr)

    # Stage 3: Build MTA-style response
    accepted = smtp["smtp_code"] == 250
    return {
        "message_id": message_id,
        "received_at": received_at,
        "status": "queued" if accepted else "deferred" if smtp["smtp_code"] < 500 else "bounced",
        "pipeline": {
            "mx_lookup": mx_result,
            "smtp_relay": smtp,
        },
        "envelope": {
            "from": req.from_addr,
            "to": req.to_addr,
            "subject": req.subject,
        },
    }


@app.get("/health")
def health():
    return {"status": "ok", "service": "mta-demo"}

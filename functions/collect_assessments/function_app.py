"""CGE-AZ pipeline — Stage 3 collector.

Timer fires nightly -> managed identity -> Defender assessments API -> Cosmos.
One immutable document per assessment per collection run. The document ID includes
the run ID, preserving historical posture instead of overwriting yesterday with
today. Deliberately boring: if you can read this file, you can defend this
pipeline's data lineage.
"""

import datetime
import hashlib
import logging
import os
import uuid

import azure.functions as func
import requests
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

app = func.FunctionApp()

ARM = "https://management.azure.com"
API_VERSION = "2021-06-01"


def _collect() -> dict:
    subscription_id = os.environ["SUBSCRIPTION_ID"]
    cosmos_endpoint = os.environ["COSMOS_ENDPOINT"]
    database = os.environ["COSMOS_DATABASE"]

    # DefaultAzureCredential resolves to the Function App's managed identity in Azure
    # (and to your `az login` session when run locally). No keys, anywhere.
    credential = DefaultAzureCredential()
    token = credential.get_token(f"{ARM}/.default").token

    run_id = str(uuid.uuid4())
    collected_at = datetime.datetime.now(datetime.timezone.utc).isoformat()

    container = (
        CosmosClient(cosmos_endpoint, credential)
        .get_database_client(database)
        .get_container_client("assessments")
    )

    url = (
        f"{ARM}/subscriptions/{subscription_id}"
        f"/providers/Microsoft.Security/assessments?api-version={API_VERSION}"
    )
    written = 0
    while url:
        resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=60)
        resp.raise_for_status()
        payload = resp.json()

        for assessment in payload.get("value", []):
            props = assessment.get("properties", {})
            resource_id = (
                props.get("resourceDetails", {}).get("Id")
                or props.get("resourceDetails", {}).get("id", "")
            )
            # Deterministic *within this run*, historical across runs. This prevents
            # a retry inside one sweep from duplicating evidence while ensuring the
            # next scheduled sweep cannot overwrite the prior posture snapshot.
            doc_id = hashlib.sha256(
                f"{run_id}|{assessment['name']}|{resource_id}".encode()
            ).hexdigest()[:32]

            container.upsert_item(
                {
                    "id": doc_id,
                    "subscriptionId": subscription_id,
                    "assessmentId": assessment["name"],
                    "displayName": props.get("displayName"),
                    "status": props.get("status", {}).get("code"),
                    "statusCause": props.get("status", {}).get("cause"),
                    "severity": props.get("metadata", {}).get("severity"),
                    "categories": props.get("metadata", {}).get("categories"),
                    "resourceId": resource_id,
                    # Accountability is captured with the evidence, not invented
                    # later by the report generator. OWNER_EMAIL is the governed
                    # environment owner supplied through Terraform.
                    "owner": os.environ.get("OWNER_EMAIL", "Unassigned"),
                    "collectedAt": collected_at,
                    "runId": run_id,
                }
            )
            written += 1

        url = payload.get("nextLink")

    logging.info("collection run %s complete: %d documents", run_id, written)
    return {"runId": run_id, "written": written, "collectedAt": collected_at}


@app.timer_trigger(schedule="0 0 5 * * *", arg_name="timer", run_on_startup=False)
def collect_nightly(timer: func.TimerRequest) -> None:
    """Nightly sweep at 05:00 UTC — midnight-ish US Eastern."""
    _collect()


@app.route(route="collect", auth_level=func.AuthLevel.FUNCTION)
def collect_now(req: func.HttpRequest) -> func.HttpResponse:
    """Manual trigger for labs and demos: hit the endpoint, get the run summary."""
    result = _collect()
    return func.HttpResponse(
        f"run {result['runId']}: {result['written']} documents at {result['collectedAt']}\n",
        status_code=200,
    )

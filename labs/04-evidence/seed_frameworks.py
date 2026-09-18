#!/usr/bin/env python3
"""Seed owned framework and crosswalk evidence.

Run once after deploying stages/03-evidence-store:

    pip install azure-cosmos azure-identity
    COSMOS_ENDPOINT=$(cd ../../stages/03-evidence-store && terraform output -raw cosmos_endpoint) \
        python3 seed_frameworks.py

Authenticates as YOU (az login) — the deployer's Cosmos data role comes from the stage.
This candidate implementation seeds both the framework catalog and the mappings
container so collect-once/report-many is demonstrable rather than aspirational.
"""

import os
import sys

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

CSF2_FUNCTIONS = {
    "GV": ("Govern", ["GV.OC", "GV.RM", "GV.RR", "GV.PO", "GV.OV", "GV.SC"]),
    "ID": ("Identify", ["ID.AM", "ID.RA", "ID.IM"]),
    "PR": ("Protect", ["PR.AA", "PR.AT", "PR.DS", "PR.PS", "PR.IR"]),
    "DE": ("Detect", ["DE.CM", "DE.AE"]),
    "RS": ("Respond", ["RS.MA", "RS.AN", "RS.CO", "RS.MI"]),
    "RC": ("Recover", ["RC.RP", "RC.CO"]),
}

CONTROL_MAPPINGS = [
    {
        "id": "map-owner-accountability",
        "controlId": "cge-require-owner-tag-rg",
        "title": "Resource-group owner accountability",
        "csf": ["GV.RR", "ID.AM"],
        "nist80053": ["PM-5", "CM-8"],
        "evidence": "Azure Policy compliance state and assessment owner field",
    },
    {
        "id": "map-public-storage-deny",
        "controlId": "cge-deny-public-blob",
        "title": "Prevent anonymous blob exposure",
        "csf": ["PR.DS-01", "PR.AA-05"],
        "nist80053": ["AC-3", "SC-7"],
        "evidence": "Policy denial event and storage configuration assessment",
    },
    {
        "id": "map-storage-diagnostics",
        "controlId": "cge-dine-storage-diagnostics",
        "title": "Enforce diagnostic coverage",
        "csf": ["DE.CM-09", "PR.PS-04"],
        "nist80053": ["AU-2", "AU-12"],
        "evidence": "Diagnostic setting deployment and AzureActivity ingestion",
    },
    {
        "id": "map-evidence-integrity",
        "controlId": "cge-worm-evidence",
        "title": "Preserve generated evidence",
        "csf": ["GV.OV-03", "PR.DS-01"],
        "nist80053": ["AU-9", "SI-12"],
        "evidence": "Unlocked time-based immutability policy and blob versions",
    },
]


def main() -> int:
    endpoint = os.environ.get("COSMOS_ENDPOINT")
    if not endpoint:
        print("Set COSMOS_ENDPOINT (see docstring).", file=sys.stderr)
        return 1

    database = CosmosClient(endpoint, DefaultAzureCredential()).get_database_client(
        os.environ.get("COSMOS_DATABASE", "grc")
    )
    container = database.get_container_client("frameworks")
    mappings = database.get_container_client("mappings")

    written = 0
    for func_id, (name, categories) in CSF2_FUNCTIONS.items():
        container.upsert_item(
            {
                "id": f"csf2-{func_id}",
                "frameworkId": "nist-csf-2.0",
                "type": "function",
                "functionId": func_id,
                "name": name,
                "categories": categories,
            }
        )
        written += 1

    container.upsert_item(
        {
            "id": "nist-csf-2.0",
            "frameworkId": "nist-csf-2.0",
            "type": "framework",
            "name": "NIST Cybersecurity Framework 2.0",
            "functions": list(CSF2_FUNCTIONS.keys()),
        }
    )
    container.upsert_item(
        {
            "id": "nist-sp-800-53-r5",
            "frameworkId": "nist-sp-800-53-r5",
            "type": "framework",
            "name": "NIST SP 800-53 Revision 5",
            "controlsUsed": sorted(
                {control for row in CONTROL_MAPPINGS for control in row["nist80053"]}
            ),
        }
    )

    mapping_count = 0
    for row in CONTROL_MAPPINGS:
        for framework_id, references in (
            ("nist-csf-2.0", row["csf"]),
            ("nist-sp-800-53-r5", row["nist80053"]),
        ):
            mappings.upsert_item(
                {
                    **row,
                    "id": f"{row['id']}-{framework_id}",
                    "frameworkId": framework_id,
                    "references": references,
                }
            )
            mapping_count += 1

    print(
        f"seeded {written + 2} framework documents and "
        f"{mapping_count} crosswalk rows into {endpoint}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

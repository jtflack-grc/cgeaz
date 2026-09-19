#!/usr/bin/env python3
"""Print redaction-safe collector run history from Cosmos DB."""

import json
import os

from azure.cosmos import CosmosClient
from azure.identity import AzureCliCredential


container = (
    CosmosClient(os.environ["COSMOS_ENDPOINT"], AzureCliCredential())
    .get_database_client("grc")
    .get_container_client("assessments")
)

rows = container.query_items(
    query="""
        SELECT TOP 20
            c.runId,
            c.trigger,
            c.sourceAssessmentCount,
            c.collectedAt,
            c.completedAt
        FROM c
        WHERE c.documentType = 'collectionRun'
        ORDER BY c.collectedAt DESC
    """,
    enable_cross_partition_query=True,
)

print(json.dumps(list(rows), indent=2))

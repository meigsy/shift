import os
import json
from datetime import datetime, timezone
from typing import Optional, Dict, Any
from uuid import uuid4

# Google Cloud Imports
from google.cloud import firestore
from google.cloud import bigquery
from google.cloud import pubsub_v1

from schemas import HealthDataBatch

# Initialize GCP Clients
db: Optional[firestore.Client] = None
bq_client: Optional[bigquery.Client] = None
publisher: Optional[pubsub_v1.PublisherClient] = None
topic_path: Optional[str] = None

def init_gcp_clients():
    """Initialize Google Cloud clients if environment variables are set."""
    global db, bq_client, publisher, topic_path
    
    try:
        # Check if we are in a GCP environment or have credentials
        if os.getenv("GCP_PROJECT_ID"):
            project_id = os.getenv("GCP_PROJECT_ID")
            db = firestore.Client(project=project_id)
            bq_client = bigquery.Client(project=project_id)
            publisher = pubsub_v1.PublisherClient()
            topic_path = publisher.topic_path(project_id, "watch_events")
            print(f"✅ GCP Clients initialized for project: {project_id}")
        else:
            print("⚠️ GCP_PROJECT_ID not set, running in offline/mock mode")
            db = None
            bq_client = None
            publisher = None
            topic_path = None
    except Exception as e:
        print(f"❌ Failed to initialize GCP clients: {e}")
        db = None
        bq_client = None
        publisher = None
        topic_path = None

# Initialize on module load
init_gcp_clients()

def process_watch_events(batch: HealthDataBatch, user_id: str) -> Dict[str, Any]:
    """
    Process a batch of health events:
    1. Deduplicate using Firestore
    2. Write to BigQuery
    3. Publish trigger to Pub/Sub
    
    Returns:
        Dict with processing results/stats
    """
    # Calculate total samples
    total_samples = (
        len(batch.heartRate) +
        len(batch.hrv) +
        len(batch.restingHeartRate) +
        len(batch.walkingHeartRateAverage) +
        len(batch.respiratoryRate) +
        len(batch.oxygenSaturation) +
        len(batch.vo2Max) +
        len(batch.steps) +
        len(batch.activeEnergy) +
        len(batch.exerciseTime) +
        len(batch.standTime) +
        len(batch.timeInDaylight) +
        len(batch.bodyMass) +
        len(batch.bodyFatPercentage) +
        len(batch.leanBodyMass) +
        len(batch.sleep) +
        len(batch.workouts)
    )
    
    # CRITICAL: trace_id is REQUIRED for 100% traceability
    trace_id = batch.trace_id
    if not trace_id:
        trace_id = str(uuid4())
        print(f"❌ CRITICAL: trace_id missing from batch! Generated: {trace_id}")
    else:
        print(f"✅ trace_id received from iOS: {trace_id}")
    
    # Use fetchedAt as part of the unique key
    fetched_at_iso = batch.fetchedAt.isoformat()
    dedup_key = f"user_{user_id}:time_{fetched_at_iso}"
    
    # 1. Deduplication (if GCP clients available)
    if db:
        try:
            doc_ref = db.collection("ingested_events").document(dedup_key)
            doc = doc_ref.get()
            if doc.exists:
                print(f"⏸️ Duplicate event detected: {dedup_key}")
                return {
                    "status": "duplicate",
                    "message": "Event already processed (deduplicated)",
                    "samples_received": total_samples
                }
            
            # Write lock record
            doc_ref.set({
                "ingested_at": datetime.now(timezone.utc),
                "user_id": user_id,
                "total_samples": total_samples
            })
        except Exception as e:
            print(f"⚠️ Firestore dedup failed (proceeding anyway): {e}")
            
    # 2. Write to BigQuery
    if bq_client:
        try:
            table_id = f"{os.getenv('GCP_PROJECT_ID')}.shift_data.watch_events"
            
            # Serialize payload
            payload = batch.model_dump_json()
            
            rows_to_insert = [
                {
                    "user_id": user_id,
                    "fetched_at": fetched_at_iso,
                    "trace_id": trace_id,
                    "payload": payload,
                    "ingested_at": datetime.now(timezone.utc).isoformat()
                }
            ]
            
            errors = bq_client.insert_rows_json(table_id, rows_to_insert)
            if errors:
                print(f"❌ BigQuery insert errors: {errors}")
                # We log but don't crash, as data is also going to Pub/Sub trigger
            else:
                print(f"✅ Written to BigQuery: {table_id} with trace_id: {trace_id}")
                
        except Exception as e:
            print(f"❌ BigQuery write failed: {e}")
            raise Exception(f"Failed to store health data: {e}")
            
    # 3. Publish Trigger to Pub/Sub
    if publisher and topic_path:
        try:
            trigger_data = {
                "user_id": user_id,
                "fetched_at": fetched_at_iso,
                "trace_id": trace_id,
                "total_samples": total_samples
            }
            data_str = json.dumps(trigger_data)
            data = data_str.encode("utf-8")
            
            # Publish trigger event (no ordering key - topic doesn't have ordering enabled)
            future = publisher.publish(
                topic_path, 
                data
            )
            message_id = future.result()
            print(f"✅ Published trigger to Pub/Sub: {message_id}")
            
        except Exception as e:
            print(f"⚠️ Pub/Sub publish failed: {e}")
    
    return {
        "status": "success",
        "message": "Health data received and ingested",
        "samples_received": total_samples
    }


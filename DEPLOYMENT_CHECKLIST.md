# Deployment Checklist - SHIFT Pipeline

## ✅ Pre-Deployment Status

### Infrastructure Ready
- ✅ `terraform.tfvars` configured with project_id
- ✅ Terraform resources defined:
  - BigQuery tables: `watch_events`, `state_estimates`, `intervention_instances`, `devices`
  - Pub/Sub topics: `watch_events`, `state_estimates`
  - Service accounts: `watch-events-sa`, `state-estimator-sa`, `intervention-selector-sa`
  - IAM permissions configured

### Code Ready
- ✅ `state_estimator` Cloud Function:
  - Reads from `watch_events` table
  - Writes to `state_estimates` table
  - Publishes to `state_estimates` Pub/Sub topic
- ✅ `intervention_selector` Cloud Functions:
  - Pub/Sub trigger: Processes state estimates
  - HTTP trigger: `GET /interventions/{id}` endpoint
- ✅ Test script: `test_pipeline.sh` for end-to-end testing

## 📋 Deployment Steps

### Step 1: Deploy Infrastructure and Cloud Functions

```bash
./deploy.sh -b
```

This will:
1. Build and push `watch-events` container image
2. Deploy Terraform resources (tables, topics, service accounts, IAM)
3. Deploy `state-estimator` Cloud Function (Pub/Sub trigger)
4. Deploy `intervention-selector` Cloud Function (Pub/Sub trigger)
5. Deploy `intervention-selector-http` Cloud Function (HTTP trigger)

**Expected time:** 5-10 minutes

### Step 2: Run End-to-End Test

After deployment completes:

```bash
./test_pipeline.sh
```

This will:
1. Insert a test watch event into BigQuery
2. Publish to `watch_events` Pub/Sub topic
3. Verify `state_estimator` creates state estimate
4. Verify `intervention_selector` creates intervention instance

### Step 3: Verify in GCP Console

Check these resources were created:

**Cloud Functions:**
- `state-estimator` (Pub/Sub trigger)
- `intervention-selector` (Pub/Sub trigger)
- `intervention-selector-http` (HTTP trigger)

**BigQuery:**
- Dataset: `shift_data`
- Tables: `watch_events`, `state_estimates`, `intervention_instances`, `devices`

**Pub/Sub:**
- Topics: `watch_events`, `state_estimates`

**Service Accounts:**
- `watch-events-sa@shift-dev-478422.iam.gserviceaccount.com`
- `state-estimator-sa@shift-dev-478422.iam.gserviceaccount.com`
- `intervention-selector-sa@shift-dev-478422.iam.gserviceaccount.com`

## 🔧 Troubleshooting

### If deployment fails:
1. Check GCP project billing is enabled
2. Ensure you have permissions: `roles/owner` or `roles/editor`
3. Check Cloud Build API is enabled: `gcloud services enable cloudbuild.googleapis.com`

### If state_estimator doesn't trigger:
1. Check Pub/Sub topic exists: `gcloud pubsub topics list`
2. Check Cloud Function logs: `gcloud functions logs read state-estimator --gen2 --limit 50`
3. Verify service account has BigQuery permissions

### If intervention_selector doesn't trigger:
1. Check `state_estimator` is publishing to `state_estimates` topic
2. Check Cloud Function logs: `gcloud functions logs read intervention-selector --gen2 --limit 50`
3. Verify service account has BigQuery and Pub/Sub permissions

## 📊 Next Steps After Deployment

1. **Monitor logs:**
   ```bash
   # State estimator logs
   gcloud functions logs read state-estimator --gen2 --limit 50 --follow

   # Intervention selector logs
   gcloud functions logs read intervention-selector --gen2 --limit 50 --follow
   ```

2. **Test with real data:**
   - Send health data from iOS app to `watch-events` endpoint
   - Or insert directly into BigQuery `watch_events` table

3. **Configure device tokens:**
   - Insert device tokens into `devices` table for push notifications
   - Or set `FALLBACK_DEVICE_TOKEN` env var for testing

4. **Set up APNs (optional):**
   - Get Apple Developer account
   - Create APNs key
   - Set env vars: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_PATH`

## 🎉 Success Criteria

Deployment is successful when:
- ✅ All Cloud Functions deploy without errors
- ✅ Test script creates state estimate in BigQuery
- ✅ Test script creates intervention instance in BigQuery
- ✅ All resources visible in GCP Console



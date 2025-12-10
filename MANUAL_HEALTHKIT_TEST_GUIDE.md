# Manual HealthKit Test Guide

This guide shows you how to manually input HealthKit data that will trigger a HIGH STRESS intervention notification.

## Goal

Create a stress score > 0.7 (HIGH) by inputting specific health data values into the iOS Health app, which will:
1. Be read by your iOS app
2. Sync to backend via `/watch_events`
3. Create a state estimate with high stress
4. Trigger intervention selector to create intervention
5. Display notification banner in iOS app

## Exact Values to Input

### 1. Heart Rate Variability (HRV)

**Value:** `25 ms`

**How to input:**
1. Open Health app on iOS simulator/device
2. Browse → Heart → Heart Rate Variability
3. Add Data → Enter: `25` ms
4. Set date/time to today, recent (e.g., 1 hour ago)

**Why this value:**
- Low HRV indicates high stress
- Formula: normalized_hrv = (25 - 20) / 40 = 0.125
- Stress contribution: (1 - 0.125) × 0.6 = **0.525**

### 2. Resting Heart Rate

**Value:** `75 bpm`

**How to input:**
1. Open Health app
2. Browse → Heart → Resting Heart Rate
3. Add Data → Enter: `75` bpm
4. Set date/time to today, recent (e.g., 1 hour ago)

**Why this value:**
- High resting HR indicates high stress
- Formula: normalized_resting_hr = (80 - 75) / 30 = 0.167
- Stress contribution: (1 - 0.167) × 0.4 = **0.333**

### 3. Sleep (Optional - for completeness)

**Duration:** `90 minutes` (1.5 hours)
**Stage:** Deep Sleep

**How to input:**
1. Open Health app
2. Browse → Sleep → Sleep Analysis
3. Add Data → Select "Deep Sleep"
4. Start time: 1 hour ago
5. End time: 30 minutes ago
6. Duration: 90 minutes

**Why this value:**
- Minimal sleep contributes to stress/fatigue
- Helps ensure high stress calculation

### 4. Steps (Optional - any value)

**Value:** `5000 steps` (or any value)

**How to input:**
1. Open Health app
2. Browse → Activity → Steps
3. Add Data → Enter: `5000` steps
4. Set date/time to today

## Expected Results

After inputting these values:

**Stress Score Calculation:**
```
Total Stress = 0.525 (from HRV) + 0.333 (from Resting HR) = 0.858
```

**Result:**
- ✅ Stress = 0.858 (> 0.7 threshold = HIGH)
- ✅ Intervention selector will create: `stress_high_notification`
- ✅ Banner will show: "Take a Short Reset - You seem overloaded. Take a 5-minute break."

## Testing Steps

1. **Input the values above** into Health app on iOS simulator/device

2. **Open your iOS app** (SHIFT app)
   - Make sure you're signed in as `mock-user-default`
   - App should be observing HealthKit updates

3. **Wait for sync** (automatic)
   - Observer queries will detect new HealthKit data
   - SyncService will automatically POST to `/watch_events`
   - Check app logs for sync activity

4. **Wait for pipeline processing** (~15 seconds)
   - Ingestion → State estimator → Intervention selector

5. **Wait for iOS polling** (up to 60 seconds)
   - iOS app polls every 60 seconds
   - Intervention should appear as banner

6. **Verify intervention appears**
   - Banner at top of screen
   - Title: "Take a Short Reset"
   - Body: "You seem overloaded. Take a 5-minute break."
   - Orange warning icon (high stress level)

## Alternative Values (if needed)

If you want to try different combinations:

| HRV (ms) | Resting HR (bpm) | Expected Stress |
|----------|------------------|-----------------|
| 25       | 75               | 0.858 (HIGH)    |
| 30       | 73               | 0.825 (HIGH)    |
| 20       | 80               | 0.900 (HIGH)    |
| 40       | 60               | 0.400 (MEDIUM)  |
| 50       | 55               | 0.200 (LOW)     |

## Troubleshooting

**Intervention doesn't appear:**
- Check iOS app logs for polling activity
- Verify sync completed (check logs)
- Check BigQuery for intervention_instances table
- Make sure you're signed in as `mock-user-default`

**Stress score too low:**
- Try lower HRV (e.g., 20ms instead of 25ms)
- Try higher resting HR (e.g., 78 bpm instead of 75 bpm)

**Sync not happening:**
- Check HealthKit authorization in iOS app
- Verify observer queries are active (check logs)
- Manually trigger sync if needed

## Next Steps

Once manual testing works, we can create an automated test app to inject these values programmatically for easier testing.







"""APNs push notification support."""

import json
import logging
import os
from typing import Optional

try:
    from apns2.client import APNsClient
    from apns2.payload import Payload
    from apns2.credentials import TokenCredentials
except ImportError:
    # APNs library is optional for now
    APNsClient = None
    Payload = None
    TokenCredentials = None

logger = logging.getLogger(__name__)


def send_push_notification(
    device_token: str,
    title: str,
    body: str,
    intervention_instance_id: str,
    apns_key_id: Optional[str] = None,
    apns_team_id: Optional[str] = None,
    apns_bundle_id: Optional[str] = None,
    apns_key_path: Optional[str] = None,
) -> bool:
    """Send push notification via APNs.

    Args:
        device_token: iOS device token
        title: Notification title
        body: Notification body
        intervention_instance_id: Intervention instance ID for payload
        apns_key_id: APNs key ID (from env var if not provided)
        apns_team_id: APNs team ID (from env var if not provided)
        apns_bundle_id: APNs bundle ID (from env var if not provided)
        apns_key_path: Path to APNs key file (from env var if not provided)

    Returns:
        True if sent successfully, False otherwise
    """
    if APNsClient is None:
        logger.warning("APNs library not available, skipping push notification")
        return False

    # Get APNs config from environment variables if not provided
    key_id = apns_key_id or os.getenv("APNS_KEY_ID")
    team_id = apns_team_id or os.getenv("APNS_TEAM_ID")
    bundle_id = apns_bundle_id or os.getenv("APNS_BUNDLE_ID", "com.shift.ios-app")
    key_path = apns_key_path or os.getenv("APNS_KEY_PATH")

    if not all([key_id, team_id, bundle_id, key_path]):
        logger.warning(
            "APNs credentials not configured. Set APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, and APNS_KEY_PATH"
        )
        return False

    try:
        # Initialize APNs client with token-based auth
        credentials = TokenCredentials(auth_key_path=key_path, auth_key_id=key_id, team_id=team_id)
        client = APNsClient(credentials=credentials, use_sandbox=True)  # Use sandbox for dev

        # Create payload with notification and custom data
        payload = Payload(
            alert={"title": title, "body": body},
            sound="default",
            badge=1,
            custom={"intervention_instance_id": intervention_instance_id},
        )

        # Send notification
        topic = bundle_id
        client.send_notification(device_token, payload, topic=topic)

        logger.info(f"Successfully sent push notification to device {device_token[:10]}...")
        return True

    except Exception as e:
        logger.error(f"Error sending push notification: {e}", exc_info=True)
        return False










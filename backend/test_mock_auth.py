"""
Test script for mock authentication endpoint.
Run this to test the backend without Apple Developer account setup.
"""

import asyncio
import httpx
import json


async def test_mock_auth():
    """Test the mock authentication endpoint."""
    base_url = "http://localhost:8080"
    
    async with httpx.AsyncClient() as client:
        # Test health endpoint
        print("1. Testing /health endpoint...")
        response = await client.get(f"{base_url}/health")
        print(f"   Status: {response.status_code}")
        print(f"   Response: {response.json()}")
        print()
        
        # Test mock auth endpoint
        print("2. Testing /auth/apple/mock endpoint...")
        mock_request = {
            "identity_token": "mock.apple.token.12345",
            "authorization_code": "mock.auth.code.67890"
        }
        
        response = await client.post(
            f"{base_url}/auth/apple/mock",
            json=mock_request
        )
        print(f"   Status: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"   ✅ Success!")
            print(f"   ID Token: {data['id_token'][:50]}...")
            print(f"   User ID: {data['user']['user_id']}")
            print(f"   Email: {data['user']['email']}")
            print()
            
            # Test /me endpoint with the mock token
            print("3. Testing /me endpoint with mock token...")
            headers = {"Authorization": f"Bearer {data['id_token']}"}
            me_response = await client.get(f"{base_url}/me", headers=headers)
            print(f"   Status: {me_response.status_code}")
            
            if me_response.status_code == 401:
                print("   ⚠️  Token not verified (expected - mock token is not a real JWT)")
                print("   This is normal - mock tokens won't pass Identity Platform verification")
            elif me_response.status_code == 200:
                print(f"   ✅ Success!")
                print(f"   User: {me_response.json()}")
            else:
                print(f"   Response: {me_response.text}")
        else:
            print(f"   ❌ Failed: {response.text}")
            print()


async def test_watch_events_mock():
    """Test the /watch_events endpoint with a mock token."""
    base_url = "http://localhost:8080"
    
    # First get a mock token
    async with httpx.AsyncClient() as client:
        mock_request = {
            "identity_token": "mock.apple.token.12345",
            "authorization_code": "mock.auth.code.67890"
        }
        
        auth_response = await client.post(
            f"{base_url}/auth/apple/mock",
            json=mock_request
        )
        
        if auth_response.status_code != 200:
            print("Failed to get mock token")
            return
        
        mock_token = auth_response.json()["id_token"]
        
        # Test /watch_events
        print("4. Testing /watch_events endpoint...")
        watch_events_data = {
            "heartRate": [
                {
                    "type": "heartRate",
                    "value": 72.0,
                    "unit": "bpm",
                    "startDate": "2025-11-25T10:00:00Z",
                    "endDate": "2025-11-25T10:01:00Z",
                    "sourceName": "Apple Watch",
                    "sourceBundle": "com.apple.Health"
                }
            ],
            "hrv": [],
            "restingHeartRate": [],
            "walkingHeartRateAverage": [],
            "respiratoryRate": [],
            "oxygenSaturation": [],
            "vo2Max": [],
            "steps": [],
            "activeEnergy": [],
            "exerciseTime": [],
            "standTime": [],
            "timeInDaylight": [],
            "bodyMass": [],
            "bodyFatPercentage": [],
            "leanBodyMass": [],
            "sleep": [],
            "workouts": [],
            "fetchedAt": "2025-11-25T12:00:00Z"
        }
        
        headers = {"Authorization": f"Bearer {mock_token}"}
        response = await client.post(
            f"{base_url}/watch_events",
            json=watch_events_data,
            headers=headers
        )
        
        print(f"   Status: {response.status_code}")
        if response.status_code == 401:
            print("   ⚠️  Token not verified (expected - mock token is not a real JWT)")
        elif response.status_code == 200:
            print(f"   ✅ Success!")
            print(f"   Response: {response.json()}")
        else:
            print(f"   Response: {response.text()}")


if __name__ == "__main__":
    print("=" * 60)
    print("Testing SHIFT Backend (Mock Mode)")
    print("=" * 60)
    print()
    
    asyncio.run(test_mock_auth())
    print()
    asyncio.run(test_watch_events_mock())
    
    print()
    print("=" * 60)
    print("Note: Mock tokens won't pass Identity Platform verification.")
    print("Use /auth/apple/mock for iOS app testing, but /me and /watch_events")
    print("will return 401 until you have real Identity Platform tokens.")
    print("=" * 60)


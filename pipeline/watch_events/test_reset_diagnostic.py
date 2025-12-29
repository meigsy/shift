#!/usr/bin/env python3
"""
Diagnostic test for /user/reset endpoint.
This will test the endpoint and show exactly what error occurs.
"""

import asyncio
import httpx
import json
import sys

BASE_URL = "http://localhost:8080"

async def test_reset_endpoint():
    """Test the /user/reset endpoint with full diagnostics."""
    print("=" * 60)
    print("Testing /user/reset endpoint")
    print("=" * 60)
    print()
    
    async with httpx.AsyncClient(timeout=10.0) as client:
        # Step 1: Check health
        print("1. Checking server health...")
        try:
            health_response = await client.get(f"{BASE_URL}/health")
            print(f"   Status: {health_response.status_code}")
            print(f"   Response: {health_response.json()}")
            if health_response.status_code != 200:
                print("   ❌ Server is not healthy!")
                return
        except Exception as e:
            print(f"   ❌ Failed to connect to server: {e}")
            print("   Make sure the server is running on http://localhost:8080")
            return
        print()
        
        # Step 2: Check routes
        print("2. Checking registered routes...")
        try:
            routes_response = await client.get(f"{BASE_URL}/debug/routes")
            if routes_response.status_code == 200:
                routes_data = routes_response.json()
                print(f"   Total routes: {routes_data['total']}")
                user_reset_found = False
                for route in routes_data['routes']:
                    if '/user/reset' in route['path']:
                        user_reset_found = True
                        print(f"   ✅ Found: {route['methods']} {route['path']}")
                if not user_reset_found:
                    print("   ❌ /user/reset route NOT FOUND in registered routes!")
                    print("   Available routes:")
                    for route in routes_data['routes']:
                        print(f"      {route['methods']} {route['path']}")
            else:
                print(f"   ⚠️ Could not check routes (status: {routes_response.status_code})")
        except Exception as e:
            print(f"   ⚠️ Could not check routes: {e}")
        print()
        
        # Step 3: Get mock auth token
        print("3. Getting mock auth token...")
        try:
            auth_response = await client.post(
                f"{BASE_URL}/auth/apple/mock",
                json={"identity_token": "test", "authorization_code": "test"}
            )
            if auth_response.status_code != 200:
                print(f"   ❌ Auth failed: {auth_response.status_code}")
                print(f"   Response: {auth_response.text}")
                return
            auth_data = auth_response.json()
            token = auth_data.get("id_token")
            if not token:
                print(f"   ❌ No token in response: {auth_data}")
                return
            print(f"   ✅ Got token: {token[:30]}...")
        except Exception as e:
            print(f"   ❌ Auth request failed: {e}")
            return
        print()
        
        # Step 4: Test /user/reset endpoint
        print("4. Testing /user/reset endpoint...")
        try:
            reset_response = await client.post(
                f"{BASE_URL}/user/reset",
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {token}"
                },
                json={"scope": "all"}
            )
            
            print(f"   Status Code: {reset_response.status_code}")
            print(f"   Response Headers: {dict(reset_response.headers)}")
            try:
                response_json = reset_response.json()
                print(f"   Response Body: {json.dumps(response_json, indent=2)}")
            except:
                print(f"   Response Body (raw): {reset_response.text}")
            
            if reset_response.status_code == 200:
                print("   ✅ SUCCESS! Endpoint works correctly.")
            elif reset_response.status_code == 404:
                print("   ❌ 404 NOT FOUND - Route not registered or path mismatch")
            elif reset_response.status_code == 422:
                print("   ❌ 422 VALIDATION ERROR - Request body parsing failed")
                print("   Check the 'detail' field in response for validation errors")
            elif reset_response.status_code == 401:
                print("   ❌ 401 UNAUTHORIZED - Authentication failed")
            elif reset_response.status_code == 500:
                print("   ❌ 500 SERVER ERROR - Check server logs for details")
            else:
                print(f"   ⚠️ Unexpected status code: {reset_response.status_code}")
                
        except httpx.TimeoutException:
            print("   ❌ Request timed out")
        except Exception as e:
            print(f"   ❌ Request failed: {e}")
            import traceback
            traceback.print_exc()
        print()
        
        print("=" * 60)
        print("Test complete!")
        print("=" * 60)

if __name__ == "__main__":
    asyncio.run(test_reset_endpoint())


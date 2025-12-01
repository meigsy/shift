"""Apple Sign in with Apple token verification and Identity Platform integration."""

import os
import json
import time
from typing import Dict, Tuple, Optional
import httpx
from jose import jwt, jwk
from jose.utils import base64url_decode
import cachetools


# Cache for Apple JWKS (cache for 1 hour)
_jwks_cache = cachetools.TTLCache(maxsize=1, ttl=3600)

APPLE_ISSUER = "https://appleid.apple.com"
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"


def get_apple_jwks() -> Dict:
    """Fetch and cache Apple's JWKS."""
    if "jwks" in _jwks_cache:
        return _jwks_cache["jwks"]
    
    response = httpx.get(APPLE_JWKS_URL, timeout=10.0)
    response.raise_for_status()
    jwks = response.json()
    _jwks_cache["jwks"] = jwks
    return jwks


def verify_apple_token(identity_token: str, client_id: str) -> Dict:
    """
    Verify Apple identity token.
    
    Args:
        identity_token: JWT token from Apple
        client_id: Apple Service ID (client ID)
    
    Returns:
        Decoded token claims
    
    Raises:
        ValueError: If token verification fails
    """
    try:
        # Decode header to get key ID
        unverified_header = jwt.get_unverified_header(identity_token)
        kid = unverified_header.get("kid")
        
        if not kid:
            raise ValueError("Token missing key ID (kid)")
        
        # Get Apple JWKS
        jwks = get_apple_jwks()
        
        # Find the matching key
        key = None
        for jwk_key in jwks.get("keys", []):
            if jwk_key.get("kid") == kid:
                key = jwk_key
                break
        
        if not key:
            raise ValueError(f"Key ID {kid} not found in Apple JWKS")
        
        # Construct RSA key from JWK
        rsa_key = jwk.construct(key)
        
        # Decode and verify token
        message, signature = str(identity_token).rsplit(".", 1)
        decoded_signature = base64url_decode(signature.encode("utf-8"))
        
        if not rsa_key.verify(message.encode("utf-8"), decoded_signature):
            raise ValueError("Token signature verification failed")
        
        # Decode token claims
        claims = jwt.get_unverified_claims(identity_token)
        
        # Verify issuer
        if claims.get("iss") != APPLE_ISSUER:
            raise ValueError(f"Invalid issuer: {claims.get('iss')}")
        
        # Verify audience (client_id)
        aud = claims.get("aud")
        if aud != client_id:
            raise ValueError(f"Invalid audience: {aud}, expected: {client_id}")
        
        # Verify expiration
        exp = claims.get("exp")
        if not exp or exp < time.time():
            raise ValueError("Token has expired")
        
        # Verify issued at
        iat = claims.get("iat")
        if not iat:
            raise ValueError("Token missing issued at time")
        
        return claims
    
    except jwt.JWTError as e:
        raise ValueError(f"JWT verification failed: {str(e)}")
    except Exception as e:
        raise ValueError(f"Token verification failed: {str(e)}")


async def exchange_with_identity_platform(
    identity_token: str,
    authorization_code: str,
    project_id: str,
    api_key: str
) -> Tuple[str, Optional[str], int, Dict]:
    """
    Exchange Apple credentials with Identity Platform.
    
    Args:
        identity_token: Verified Apple identity token
        authorization_code: Apple authorization code
        project_id: GCP project ID
        api_key: Identity Platform API key
    
    Returns:
        Tuple of (id_token, refresh_token, expires_in, user_info)
    
    Raises:
        ValueError: If exchange fails
    """
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp"
    
    params = {
        "key": api_key
    }
    
    # Get Apple client ID from environment
    apple_client_id = os.getenv("APPLE_CLIENT_ID")
    if not apple_client_id:
        raise ValueError("APPLE_CLIENT_ID environment variable not set")
    
    # Get request URI (redirect URI configured in Identity Platform)
    request_uri = f"https://{project_id}.firebaseapp.com/__/auth/handler"
    
    payload = {
        "postBody": f"id_token={identity_token}&access_token={authorization_code}",
        "requestUri": request_uri,
        "returnIdpCredential": True,
        "returnSecureToken": True
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(url, params=params, json=payload, timeout=30.0)
            response.raise_for_status()
            
            data = response.json()
            
            # Check for errors
            if "error" in data:
                error = data["error"]
                raise ValueError(f"Identity Platform error: {error.get('message', 'Unknown error')}")
            
            id_token = data.get("idToken")
            refresh_token = data.get("refreshToken")
            expires_in = int(data.get("expiresIn", 3600))
            
            # Extract user info
            user_info = {
                "localId": data.get("localId"),
                "user_id": data.get("localId"),  # Alias for consistency
                "email": data.get("email"),
                "displayName": data.get("displayName"),
            }
            
            if not id_token:
                raise ValueError("Identity Platform response missing idToken")
            
            return id_token, refresh_token, expires_in, user_info
    
    except httpx.HTTPStatusError as e:
        error_body = e.response.text
        raise ValueError(f"Identity Platform HTTP error: {e.response.status_code} - {error_body}")
    except Exception as e:
        raise ValueError(f"Identity Platform exchange failed: {str(e)}")


async def authenticate_with_apple(
    identity_token: str,
    authorization_code: str
) -> Tuple[str, Optional[str], int, Dict]:
    """
    Complete Apple authentication flow.
    
    1. Verify Apple identity token
    2. Exchange with Identity Platform
    3. Return Identity Platform tokens and user info
    
    Args:
        identity_token: Apple identity token
        authorization_code: Apple authorization code
    
    Returns:
        Tuple of (id_token, refresh_token, expires_in, user_info)
    
    Raises:
        ValueError: If authentication fails
    """
    # Get configuration from environment
    apple_client_id = os.getenv("APPLE_CLIENT_ID")
    project_id = os.getenv("GCP_PROJECT_ID") or os.getenv("IDENTITY_PLATFORM_PROJECT_ID")
    api_key = os.getenv("IDENTITY_PLATFORM_API_KEY")
    
    if not apple_client_id:
        raise ValueError("APPLE_CLIENT_ID environment variable not set")
    if not project_id:
        raise ValueError("GCP_PROJECT_ID or IDENTITY_PLATFORM_PROJECT_ID environment variable not set")
    if not api_key:
        raise ValueError("IDENTITY_PLATFORM_API_KEY environment variable not set")
    
    # Verify Apple token
    apple_claims = verify_apple_token(identity_token, apple_client_id)
    
    # Exchange with Identity Platform
    id_token, refresh_token, expires_in, user_info = await exchange_with_identity_platform(
        identity_token=identity_token,
        authorization_code=authorization_code,
        project_id=project_id,
        api_key=api_key
    )
    
    return id_token, refresh_token, expires_in, user_info






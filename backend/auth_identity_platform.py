"""Identity Platform ID token verification."""

import os
import time
from typing import Dict
import httpx
from jose import jwt, jwk
from jose.utils import base64url_decode
import cachetools


# Cache for Google JWKS (cache for 1 hour)
_jwks_cache = cachetools.TTLCache(maxsize=1, ttl=3600)

GOOGLE_ISSUER_PREFIX = "https://securetoken.google.com/"


def get_google_jwks(project_id: str) -> Dict:
    """Fetch and cache Google's JWKS for Identity Platform."""
    cache_key = f"jwks_{project_id}"
    if cache_key in _jwks_cache:
        return _jwks_cache[cache_key]
    
    # Identity Platform uses Firebase Auth JWKS endpoint
    jwks_url = f"https://www.googleapis.com/identitytoolkit/v3/relyingparty/publicKeys"
    
    response = httpx.get(jwks_url, timeout=10.0)
    response.raise_for_status()
    jwks = response.json()
    _jwks_cache[cache_key] = jwks
    return jwks


def verify_identity_platform_token(token: str) -> Dict:
    """
    Verify Identity Platform ID token.
    
    Args:
        token: Identity Platform ID token (JWT)
    
    Returns:
        Decoded token claims
    
    Raises:
        ValueError: If token verification fails
    """
    try:
        # Decode header to get key ID
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")
        
        if not kid:
            raise ValueError("Token missing key ID (kid)")
        
        # Get project ID from environment
        project_id = os.getenv("GCP_PROJECT_ID") or os.getenv("IDENTITY_PLATFORM_PROJECT_ID")
        if not project_id:
            raise ValueError("GCP_PROJECT_ID or IDENTITY_PLATFORM_PROJECT_ID environment variable not set")
        
        # Get Google JWKS
        jwks = get_google_jwks(project_id)
        
        # Find the matching key
        key = None
        for jwk_key in jwks.get("keys", []):
            if jwk_key.get("kid") == kid:
                key = jwk_key
                break
        
        if not key:
            raise ValueError(f"Key ID {kid} not found in Google JWKS")
        
        # Construct RSA key from JWK
        rsa_key = jwk.construct(key)
        
        # Decode and verify token
        message, signature = str(token).rsplit(".", 1)
        decoded_signature = base64url_decode(signature.encode("utf-8"))
        
        if not rsa_key.verify(message.encode("utf-8"), decoded_signature):
            raise ValueError("Token signature verification failed")
        
        # Decode token claims
        claims = jwt.get_unverified_claims(token)
        
        # Verify issuer
        expected_issuer = f"{GOOGLE_ISSUER_PREFIX}{project_id}"
        if claims.get("iss") != expected_issuer:
            raise ValueError(f"Invalid issuer: {claims.get('iss')}, expected: {expected_issuer}")
        
        # Verify audience (should be the project ID)
        aud = claims.get("aud")
        if aud != project_id:
            raise ValueError(f"Invalid audience: {aud}, expected: {project_id}")
        
        # Verify expiration
        exp = claims.get("exp")
        if not exp or exp < time.time():
            raise ValueError("Token has expired")
        
        # Verify issued at
        iat = claims.get("iat")
        if not iat:
            raise ValueError("Token missing issued at time")
        
        # Verify auth_time (should be present)
        auth_time = claims.get("auth_time")
        if not auth_time:
            raise ValueError("Token missing auth_time")
        
        return claims
    
    except jwt.JWTError as e:
        raise ValueError(f"JWT verification failed: {str(e)}")
    except Exception as e:
        raise ValueError(f"Token verification failed: {str(e)}")


def get_user_from_token(claims: Dict) -> str:
    """
    Extract user ID from verified token claims.
    
    Args:
        claims: Decoded token claims
    
    Returns:
        User ID (sub claim)
    
    Raises:
        ValueError: If user ID not found
    """
    user_id = claims.get("sub") or claims.get("user_id")
    if not user_id:
        raise ValueError("Token missing user ID (sub)")
    return user_id



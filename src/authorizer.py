import os

import jwt


def lambda_handler(event, context):
    token = _extrair_token(event)

    if not token:
        return {"isAuthorized": False}

    try:
        claims = jwt.decode(
            token,
            os.environ["JWT_SECRET"],
            algorithms=["HS256"],
            issuer="auth-api",
        )
    except jwt.PyJWTError:
        return {"isAuthorized": False}

    return {
        "isAuthorized": True,
        "context": {
            "sub": str(claims.get("sub", "")),
            "type": str(claims.get("type", "")),
        },
    }


def _extrair_token(event):
    headers = event.get("headers") or {}
    auth_header = headers.get("authorization") or headers.get("Authorization")

    if not auth_header or not auth_header.startswith("Bearer "):
        return None

    return auth_header[len("Bearer "):]

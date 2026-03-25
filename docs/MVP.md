# MVP Implementation Guide

## Core Foundation (Priority 1)

This implementation provides the essential features for user identity, authentication, content creation, and social interactions.

### Features Implemented

#### 1. Identity & Auth
- **Registration**: `POST /api/auth/register` - Create new account with username
- **WebAuthn/Passkeys**: Challenge/verify endpoints for passwordless auth
- **OAuth2**: GitHub and Google login via `/auth/:provider/callback`
- **Sessions**: Token-based authentication with 7-day expiry
- **API Tokens**: Bearer token authentication for all protected endpoints

#### 2. Profile Management
- **View Profile**: `GET /api/profiles/:username`
- **Update Profile**: `PUT /api/profile` (authenticated)
- Fields: display_name, avatar_url, banner_url, bio

#### 3. Notes (Publishing)
- **Create Note**: `POST /api/notes` (authenticated)
- **List Public Notes**: `GET /api/notes`
- **List User Notes**: `GET /api/users/:username/notes`
- **Visibility**: `public` or `followers` only

#### 4. Social Graph
- **Follow**: `POST /api/follow` with `{"username": "target"}`
- **Unfollow**: `POST /api/unfollow` with `{"username": "target"}`
- **List Followers**: `GET /api/users/:username/followers`

### Database Schema

New tables:
- `notes` - User-generated content with visibility control
- `sessions` - Token-based authentication sessions
- `webauthn_credentials` - Passkey storage
- `oauth_connections` - OAuth provider linkage

Enhanced `accounts` table with profile fields.

### Setup

1. Install dependencies:
```bash
cd elixir
mix deps.get
```

2. Set OAuth environment variables (optional):
```bash
export GITHUB_CLIENT_ID=your_id
export GITHUB_CLIENT_SECRET=your_secret
export GOOGLE_CLIENT_ID=your_id
export GOOGLE_CLIENT_SECRET=your_secret
```

3. Run migrations:
```bash
mix ecto.migrate
```

4. Start server:
```bash
mix run --no-halt
```

### Example Usage

#### Register and Login
```bash
# Register
curl -X POST http://localhost:4000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"alice"}'

# Response: {"account_id":1,"token":"abc123..."}
```

#### Update Profile
```bash
curl -X PUT http://localhost:4000/api/profile \
  -H "Authorization: Bearer abc123..." \
  -H "Content-Type: application/json" \
  -d '{"display_name":"Alice","bio":"Hello world!"}'
```

#### Create Note
```bash
curl -X POST http://localhost:4000/api/notes \
  -H "Authorization: Bearer abc123..." \
  -H "Content-Type: application/json" \
  -d '{"content":"My first post!","visibility":"public"}'
```

#### Follow User
```bash
curl -X POST http://localhost:4000/api/follow \
  -H "Authorization: Bearer abc123..." \
  -H "Content-Type: application/json" \
  -d '{"username":"bob"}'
```

### Architecture Notes

- **Stateless Auth**: Sessions stored in DB, tokens are opaque random values
- **Password-free**: WebAuthn for biometric/hardware key auth
- **OAuth Integration**: Automatic account creation on first OAuth login
- **Visibility Control**: Notes can be public or followers-only
- **Minimal Dependencies**: Uses existing Ecto, Plug, and Bandit stack

### Next Steps

After MVP is validated:
- Add media upload support
- Implement timeline aggregation
- Add notifications
- Enhance visibility controls (mentions, DMs)
- Add rate limiting
- Implement proper WebAuthn challenge storage (currently placeholder)

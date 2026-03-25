# Documentation Index

## Quick Start
- [README.md](../README.md) - Project overview and quick start
- [ARCHITECTURE_SPEC.md](ARCHITECTURE_SPEC.md) - Detailed architecture specification

## Priority 2: Real-time Feeds & Streaming
- [PRIORITY_2_SUMMARY.md](PRIORITY_2_SUMMARY.md) - Implementation summary
- [STREAMING.md](STREAMING.md) - Detailed streaming guide
- [STREAMING_QUICKREF.md](STREAMING_QUICKREF.md) - Quick reference
- [test_streaming.sh](test_streaming.sh) - Test script
- [streaming_demo.html](streaming_demo.html) - Browser demo

## Priority 3: ActivityPub Federation
- [PRIORITY_3_FEDERATION.md](PRIORITY_3_FEDERATION.md) - Comprehensive implementation guide
- [FEDERATION_QUICKREF.md](FEDERATION_QUICKREF.md) - Quick reference
- [FEDERATION_DEPLOYMENT.md](FEDERATION_DEPLOYMENT.md) - Production deployment guide
- [PRIORITY_3_COMPLETE.md](PRIORITY_3_COMPLETE.md) - Completion summary
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - Technical implementation details
- [test_federation.sh](test_federation.sh) - Test script

## Priority 4: Misskey Features & Media
- [PRIORITY_4_MISSKEY.md](PRIORITY_4_MISSKEY.md) - Media, emojis, reactions, MFM, polls

## Priority 5: Moderation & Extended UX
- [PRIORITY_5_MODERATION.md](PRIORITY_5_MODERATION.md) - Moderation, bookmarks, push, articles

## Implementation Details
- [IMPLEMENTATION_TREE.md](IMPLEMENTATION_TREE.md) - File structure overview
- [IMPLEMENTATION_COMPLETE.md](IMPLEMENTATION_COMPLETE.md) - Priority 2 completion details
- [MVP.md](MVP.md) - MVP specification

## Testing

### Priority 2 (Streaming)
```bash
cd docs
./test_streaming.sh
# Open streaming_demo.html in browser
```

### Priority 3 (Federation)
```bash
cd docs
./test_federation.sh
```

## Quick Reference

### API Endpoints
- WebFinger: `GET /.well-known/webfinger`
- Actor: `GET /users/:name`
- Inbox: `POST /users/:name/inbox`
- Outbox: `GET /users/:name/outbox`
- Feeds: `GET /api/feeds/{home,local}`
- Streaming: `GET /api/streaming/{home,local}`
- Like: `POST /api/likes`
- Boost: `POST /api/boosts`
- Undo: `POST /api/undo`
- Reactions: `POST /api/reactions`
- Polls: `POST /api/polls/vote`
- Mute/Block: `POST /api/{mute,block}`
- Reports: `POST /api/reports`
- Bookmarks: `POST /api/bookmarks`
- Articles: `POST /api/articles`

### Key Directories
- Elixir: `elixir/lib/sukhi_fedi/`
- Deno: `deno/handlers/`
- Config: `elixir/config/config.exs`
- Migrations: `elixir/priv/repo/migrations/`

## License
All code is licensed under MPL-2.0.

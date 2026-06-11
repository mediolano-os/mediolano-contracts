# User Achievements

An on-chain achievement, badge, and leaderboard system for the Mediolano platform. Tracks creator activity, issues verifiable credentials, and maintains a merit-based ranking — all without external dependencies.

## Overview

`UserAchievements` is an owner-administered contract that records activity events, evaluates them against configured achievement thresholds, issues badges and certificates, and maintains a ranked leaderboard. All state is on-chain and queryable by frontends and indexers via emitted events.

## Architecture

```
User Activity → record_activity_event
                    ↓
             Achievement evaluation
                    ↓
          Badge / Certificate issuance
                    ↓
         Leaderboard & point update
```

## Key Types

```cairo
enum AchievementType  { /* 9 types */ }
enum ActivityType     { AssetMinted, AssetSold, ... /* 9 types */ }
enum BadgeType        { /* 9 types */ }
enum CertificateType  { /* 7 types */ }

struct UserProfile {
    total_points: u32,
    rank: u32,
    achievements_count: u32,
    badges_count: u32,
}
```

## Interface

```cairo
// Owner-only writes
fn record_achievement(user, achievement_type, metadata_uri)
fn record_activity_event(user, activity_type, value)
fn issue_badge(user, badge_type, metadata_uri)
fn issue_certificate(user, cert_type, metadata_uri)
fn set_activity_points(activity_type, points)

// Public reads
fn get_user_profile(user) -> UserProfile
fn get_user_achievements(user, page, page_size) -> Span<Achievement>
fn get_user_badges(user) -> Span<Badge>
fn get_user_certificates(user) -> Span<Certificate>
fn get_leaderboard(page, page_size) -> Span<(ContractAddress, u32)>
fn get_rank(user) -> u32
```

## Events

| Event | Indexed fields |
|---|---|
| `AchievementRecorded` | user, achievement_type |
| `ActivityEventRecorded` | user, activity_type |
| `BadgeIssued` | user, badge_type |
| `CertificateIssued` | user, cert_type |
| `LeaderboardUpdated` | user, new_rank |
| `PointsUpdated` | user, total_points |
| `ProfileUpdated` | user |

## Development

```bash
cd contracts/User-Achievements

# Build
scarb build

# Test
scarb test
```

> **Status: Pre-production.** Do not use in production without a security review.

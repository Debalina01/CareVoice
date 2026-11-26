# CareVoice Project Progress & Implementation Tracker

**Last Updated:** 2026-10-24  
**Project:** CareVoice — Caregiver-Relay Medicine Reminder System  
**Repository Workspace:** `D:\Anirban Projects\dummy for me\FLUTTER  APP`  
**Solution Target:** .NET 8 LTS (`backend/CareVoice.sln`) & Flutter 3.47.2 (`mobile/carevoice_app`)

---

## 1. Feature Status Matrix

| Feature / Module | Status | Verified | Description |
| :--- | :---: | :---: | :--- |
| **Domain & Data Architecture** | Completed | Yes | All 10 domain entities, EF Core configurations, migrations, and relationships. |
| **Authentication & JWT** | Completed | Yes | Register, Login, Refresh token rotation, BCrypt password hashing, and auto-seeded Demo Caregiver. |
| **CORS & Web Sandbox** | Completed | Yes | Preflight OPTIONS and cross-origin access enabled for Flutter Web (`http://localhost:8080`). |
| **Phase 2: Family Members API** | Completed | Yes | CRUD + soft-delete for authorized members (`GET`, `POST`, `PUT`, `DELETE /api/family-members`). |
| **Phase 2: Invites & Permissions** | Completed | Yes | Cryptographic invite tokens, acceptance flow, `FamilyPermissions` enforcement (`CanSetReminders`, `CanViewLogs`). |
| **Phase 2: Flutter UI Integration** | Completed | Yes | `FamilyScreen` with member list, add/edit dialogs, invite tokens, permission indicators. |
| **Phase 3: Medicines & Schedules** | Completed | Yes | `MedicinesController`, `SchedulesController`, recurring schedules with day bitmasks and permission checks. |
| **Phase 3: 48-Hour Sync & Offline SQLite** | Completed | Yes | `GET /api/schedules/sync`, `cached_schedules`, `pending_logs` queue, web-safe local DB. |
| **Phase 3: Append-Only Logs** | Completed | Yes | Strictly append-only `POST /api/logs/sync` with client UUID `ClientLogId` and idempotent deduplication. |
| **Phase 3: Hangfire Missed Relays** | Completed | Yes | `MissedReminderRelayService` detecting overdue doses past grace period and generating creator push alerts. |
| **Phase 4: Flutter Dashboard Experience** | Completed | Yes | Real-time Caregiver dashboard, live upcoming dose list, Taken/Snooze/Skip buttons with TTS, adherence history. |
| **Automated Test Suite** | Completed | Yes | 10/10 xUnit backend tests passing; 6/6 Flutter unit & widget tests passing. |

---

## 2. API Endpoints Documentation

### Authentication (`/api/auth`)
- `POST /api/auth/register` — Registers caregiver account and auto-creates default "Self" `FamilyMember`.
- `POST /api/auth/login` — Returns JWT access token (1h expiry), refresh token (7d expiry), and user profile.
- `POST /api/auth/refresh` — Rotates refresh token and issues new JWT access token.

### Family Members (`/api/family-members`)
- `GET /api/family-members` — Returns all family members accessible to the authenticated user.
- `GET /api/family-members/{id}` — Returns specific family member details if authorized.
- `POST /api/family-members` — Creates a new family member under caller's account.
- `PUT /api/family-members/{id}` — Updates member details (name, relation, language, voice).
- `DELETE /api/family-members/{id}` — Soft-deletes a family member (blocks deletion of Self).

### Invites & Permissions (`/api/invites`)
- `POST /api/invites` — Generates a 32-byte cryptographic hex token for an external contact.
- `GET /api/invites` — Lists invitations sent by caller.
- `POST /api/invites/accept` — Accepts invite token and establishes `FamilyPermissions` (`CanSetReminders`, `CanViewLogs`).
- `DELETE /api/invites/{id}` — Cancels a pending invite.

### Medicines (`/api/medicines`)
- `GET /api/medicines` — Returns medicines for caller and authorized family members.
- `GET /api/medicines/{id}` — Returns medicine by ID.
- `POST /api/medicines` — Creates medicine with dosage, instructions, and food relation.
- `PUT /api/medicines/{id}` — Updates medicine details.
- `DELETE /api/medicines/{id}` — Deactivates medicine (`IsDeleted = true`).

### Schedules & Sync (`/api/schedules`)
- `GET /api/schedules` — Returns recurring schedules.
- `POST /api/schedules` — Creates recurring schedule with time of day and day-of-week bitmask.
- `PUT /api/schedules/{id}` — Modifies schedule time or days.
- `DELETE /api/schedules/{id}` — Deactivates schedule.
- `GET /api/schedules/sync` — Generates upcoming 48-hour dose instances with target recipient voice settings.

### Append-Only Logs (`/api/logs`)
- `POST /api/logs/sync` — Synchronizes recipient Taken/Snoozed/Skipped actions with `ClientLogId` idempotency.
- `GET /api/logs/history` — Returns adherence history filtered by member or date.

---

## 3. Test Verification Summary
- **Backend Build (`dotnet build`):** 0 Errors, 0 Warnings.
- **Backend Automated Unit Tests (`dotnet test`):** 10/10 Passed (100%).
  - `FamilyMemberServiceTests` (3 tests passed)
  - `InviteAndPermissionServiceTests` (3 tests passed)
  - `MedicineAndScheduleServiceTests` (3 tests passed)
  - `MissedReminderRelayServiceTests` (1 test passed)
- **Backend Live Integration Tests:**
  - `test_auth.ps1`: 3/3 checks passed.
  - `test_phase2.ps1`: 10/10 checks passed.
  - `test_phase3.ps1`: 7/7 checks passed.
- **Flutter Code Analysis (`flutter analyze`):** 0 issues found.
- **Flutter Test Suite (`flutter test`):** 6/6 tests passed.

---

## 4. Modified & Created Files

### Backend (`backend/src/` & `backend/tests/`)
- `src/CareVoice.Application/DTOs/FamilyMemberDtos.cs`
- `src/CareVoice.Application/DTOs/InviteDtos.cs`
- `src/CareVoice.Application/DTOs/MedicineDtos.cs`
- `src/CareVoice.Application/Interfaces/IPermissionService.cs`
- `src/CareVoice.Application/Interfaces/IFamilyMemberService.cs`
- `src/CareVoice.Application/Interfaces/IInviteService.cs`
- `src/CareVoice.Application/Interfaces/IMedicineService.cs`
- `src/CareVoice.Application/Interfaces/IScheduleService.cs`
- `src/CareVoice.Application/Interfaces/ILogService.cs`
- `src/CareVoice.Application/Interfaces/IMissedReminderRelayService.cs`
- `src/CareVoice.Infrastructure/Services/PermissionService.cs`
- `src/CareVoice.Infrastructure/Services/FamilyMemberService.cs`
- `src/CareVoice.Infrastructure/Services/InviteService.cs`
- `src/CareVoice.Infrastructure/Services/MedicineService.cs`
- `src/CareVoice.Infrastructure/Services/ScheduleService.cs`
- `src/CareVoice.Infrastructure/Services/LogService.cs`
- `src/CareVoice.Infrastructure/Services/MissedReminderRelayService.cs`
- `src/CareVoice.Infrastructure/DependencyInjection.cs`
- `src/CareVoice.Api/Controllers/FamilyMembersController.cs`
- `src/CareVoice.Api/Controllers/InvitesController.cs`
- `src/CareVoice.Api/Controllers/MedicinesController.cs`
- `src/CareVoice.Api/Controllers/SchedulesController.cs`
- `src/CareVoice.Api/Controllers/LogsController.cs`
- `src/CareVoice.Scheduler/Worker.cs`
- `src/CareVoice.Scheduler/Program.cs`
- `tests/CareVoice.Tests/CareVoice.Tests.csproj`
- `tests/CareVoice.Tests/FamilyMemberServiceTests.cs`
- `tests/CareVoice.Tests/InviteAndPermissionServiceTests.cs`
- `tests/CareVoice.Tests/MedicineAndScheduleServiceTests.cs`
- `tests/CareVoice.Tests/MissedReminderRelayServiceTests.cs`

### Mobile (`mobile/carevoice_app/`)
- `lib/domain/models.dart` (Updated with `FamilyMemberModel`, `InviteModel`, `DoseSyncModel`, `DoseHistoryModel`)
- `lib/data/local_db.dart` (Added web fallback and sync status tracking)
- `lib/data/family_repository.dart` (Full family and invite API client)
- `lib/data/medicine_repository.dart` (Full medicines, schedules, 48h sync, and offline action client)
- `lib/presentation/family/family_screen.dart` (Complete family management UI)
- `lib/presentation/medicines/medicines_screen.dart` (Complete medicines & schedules UI)
- `lib/presentation/dashboard/dashboard_screen.dart` (Integrated dashboard with upcoming doses, live TTS voice alerts, Taken/Snooze/Skip buttons, and adherence cards)
- `test/family_test.dart`
- `test/medicine_test.dart`

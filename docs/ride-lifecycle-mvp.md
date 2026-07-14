# Savari Ride Lifecycle MVP

> Superseded by [Savari And Dastak Launch Design](superpowers/specs/2026-07-15-savari-dastak-launch-design.md). Retained only as historical MVP context.

## Product Goal

Savari's first real milestone is not broad feature coverage. It is one complete ride that two authenticated users can finish end to end:

1. Passenger requests a ride.
2. Nearby driver accepts it.
3. Driver navigates to pickup.
4. Driver can only mark arrival when physically close to pickup.
5. Passenger boards using a boarding code.
6. Driver navigates to drop-off.
7. Driver completes the ride.
8. Passenger sees the completed state.

## Canonical Ride State Machine

Ride status should move in this order:

```text
requested
accepted
arrived
boarded
in_progress
completed
```

Terminal exceptions:

```text
cancelled_by_passenger
cancelled_by_driver
expired
```

## State Responsibilities

### requested

- Created by passenger.
- Contains passenger ID, pickup coordinates, drop-off coordinates, vehicle type, estimated fare, distance, and ETA.
- Visible to eligible nearby online drivers.

### accepted

- Created by `accept_ride`.
- Exactly one driver owns the ride.
- Passenger sees assigned driver movement.
- Driver sees navigation to pickup.
- Current database migrations use `assigned` for this state. The product language should normalize this to `accepted` later, but the MVP supports both names.

### arrived

- Driver has reached pickup.
- Client should disable the `Arrive` action until the driver's current GPS point is within the configured threshold.
- Backend must enforce the same threshold before accepting the status transition.

### boarded

- Passenger shares boarding code.
- Driver enters code.
- Backend verifies the code before moving the ride to `boarded`.

### in_progress

- Driver has started the ride.
- Driver navigation target changes from pickup to drop-off.
- Passenger sees active trip state.

### completed

- Driver has ended the ride.
- Fare is unlocked.
- Both passenger and driver see final status.

## iOS MVP Rules

- Driver active ride screen must show the current navigation target: pickup before boarding/start, drop-off after boarding/start.
- Driver active ride screen must show distance from current driver GPS to the active target.
- `Arrive` must be disabled until the driver is close to pickup.
- `Enter Code` should only be available after arrival.
- `Start Ride` should only be available after the boarding code is verified or the ride is already `boarded`.
- `End Ride` should only be available while `in_progress`.

## Supabase MVP Rules

- Public tables stay protected by RLS.
- Ride transitions should happen through controlled RPCs, not raw table updates from arbitrary screens.
- Existing client-side arrival gating is a UX guard only. A backend `mark_driver_arrived` RPC should be added before production to enforce distance using the latest stored driver location.

## Deferred

- Payments.
- Ratings.
- Promotions.
- Driver document review workflow.
- Admin dashboard.
- Android.
- In-app turn-by-turn navigation.

# Native Reimagined scenery

Decorative assets only: not catalogue imagery, inventory, prices or promised food.

- `native-staff.*` and `native-staff-*.png`: derived from the repository's MakeHuman CC0-1.0 character, SHA-256 `adf9f73504acff6a6747901fb804d3157c92bc37544bb3843af25e5cb838151f`. Original attribution/licence record: `Web/MarketplaceWeb/src/assets/reimagined/STAFF-LICENSE.md`. Reproduce offline with `scripts/prepare-dastak-native-staff.py`. The exporter bakes relaxed arms and keeps real left/right eyelid deformation. No historical RPM assets are used.
- Pavement scans: Poly Haven Concrete Pavement, CC0, https://polyhaven.com/a/concrete_pavement . Original provenance: `EXTERIOR-LICENSE.md` beside the web assets.
- Wood scans: Poly Haven Wood Floor, Dimitrios Savva, CC0, https://polyhaven.com/a/wood_floor . Original provenance: `STAFF-LICENSE.md` beside the web assets.
- Decorative café photographs: Horizon Content (burger), Aakash Goel (fries), Jeremy Li (chicken), Pexels License. Original image URLs/terms recorded in the web `RESTAURANT-LICENSE.md`. No endorsement, product identity or availability implied.
- Room, counter, apron/cap, planting and package geometry are locally authored. No purchased assets or image-generation requests.
- Native café architecture, fitted apron/cap and folded-leaf construction follow the repository's authored web scene/uniform/planting code. Stone/quartz/bark grain and cloud noise are generated locally in code; no additional raster assets or external services are used. Decorative sky/moon placement is not astronomical data.

Native renderer: SceneKit/Metal behind SwiftUI. SceneKit is deprecated in newer Apple SDKs; keep its adapter isolated for a future RealityKit migration. This implementation is not a claim of AAA graphics, visual parity approval or measured real-phone performance.

Day/night follows the device clock without permission. Nearby-area live weather is explicit opt-in, sends only two-decimal coordinates, and is throttled. Development uses the existing Open-Meteo forecast API. Release requires a configured HTTPS weather service with appropriate commercial-use permission; no public noncommercial service is silently enabled for release. No account token or delivery address is transmitted.

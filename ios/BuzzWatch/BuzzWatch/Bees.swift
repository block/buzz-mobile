import SwiftUI

/// Shown while the watch reaches the relay: the Buzz bees, flying.
struct Connecting: View {
    var body: some View {
        ZStack {
            BeeSwarm().accessibilityHidden(true)
            Text("Connecting…").font(.headline)
        }
        .ignoresSafeArea()
    }
}

/// Bee geometry from the phone app's assets/images/welcome-bee.svg (viewBox 466 x 309).
private let beeSize = CGSize(width: 466, height: 309)
private let bee: Path = {
    let wingSpan = CGRect(x: 0, y: 62.8, width: 183.4, height: 183.4)
    var path = Path(ellipseIn: wingSpan).intersection(Path(CGRect(x: 0, y: 0, width: 128, height: 309)))
    path.addPath(
        Path(ellipseIn: wingSpan.offsetBy(dx: 282.6, dy: 0)).intersection(Path(CGRect(x: 338, y: 0, width: 128, height: 309)))
    )
    path.addRoundedRect(in: CGRect(x: 128, y: 0, width: 210, height: 309), cornerSize: CGSize(width: 34, height: 34))
    path.addEllipse(in: CGRect(x: 166.3, y: 57.4, width: 54, height: 54))
    path.addEllipse(in: CGRect(x: 249, y: 57.4, width: 54, height: 54))
    path.addRoundedRect(in: CGRect(x: 166.3, y: 157.2, width: 136.9, height: 38.3), cornerSize: CGSize(width: 5, height: 5))
    path.addRoundedRect(in: CGRect(x: 166.9, y: 235.1, width: 136.2, height: 37.6), cornerSize: CGSize(width: 5, height: 5))
    return path
}()

/// The phone's swarm is tuned for a phone; on a watch everything is drawn at this share of that size.
private let watchScale: CGFloat = 0.5
private let step = 1.0 / 60.0

private struct BeeSwarm: View {
    @State private var motion = BeeMotion()
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        TimelineView(.animation(paused: still)) { timeline in
            Canvas { context, size in
                motion.resize(CGSize(width: size.width / watchScale, height: size.height / watchScale))
                if !still { motion.advance(to: timeline.date) }
                let arrived = still ? 1 : 1 - pow(1 - min(1, max(0, motion.elapsed / 1.05)), 3)
                let drawn = 46 * watchScale / beeSize.width
                for (index, bee) in motion.bees.enumerated() {
                    let at = bee.entrance + (bee.position - bee.entrance) * arrived
                    var layer = context
                    layer.translateBy(x: at.x * watchScale, y: at.y * watchScale)
                    layer.rotate(by: .radians(bee.rotation))
                    layer.scaleBy(x: drawn, y: drawn)
                    layer.translateBy(x: -beeSize.width / 2, y: -beeSize.height / 2)
                    layer.fill(BuzzWatch.bee, with: .color(index % 2 == 1 ? Theme.pale : Theme.primary), style: FillStyle(eoFill: true))
                }
            }
        }
    }
}

private struct Bee {
    let seed: Double
    var position: CGPoint
    var velocity = CGPoint.zero
    var home: CGPoint
    var entrance: CGPoint
    var heading: Double
    var rotation: Double

    init(size: CGSize, index: Int) {
        let n = Double(index + 1)
        seed = (n * 0.7548776662).truncatingRemainder(dividingBy: 1)
        let u = (0.5 + n / 1.324717957244746).truncatingRemainder(dividingBy: 1)
        let v = (0.5 + n / pow(1.324717957244746, 2)).truncatingRemainder(dividingBy: 1)
        let bearing = seed * .pi * 2 + Double(index) * 0.37
        position = CGPoint(x: u * size.width, y: v * size.height)
        home = CGPoint(x: (0.12 + u * 0.76) * size.width, y: (0.14 + v * 0.72) * size.height)
        entrance = CGPoint(
            x: size.width / 2 + cos(bearing) * (size.width * 0.7 + 46),
            y: size.height / 2 + sin(bearing) * (size.height * 0.7 + 31)
        )
        heading = seed * .pi * 2
        rotation = seed * .pi * 2 + .pi / 2
    }
}

/// The phone app's welcome-swarm flight model (website_bee_motion.dart):
/// wandering heading, periodic darting, separation, home attraction and soft
/// edge turns. Fewer bees, since the screen is small.
private final class BeeMotion {
    private(set) var size = CGSize.zero
    private(set) var bees: [Bee] = []
    private(set) var elapsed = 0.0
    private var previous: Date?
    private var remainder = 0.0
    /// How near an edge a bee starts turning back; narrower than the phone's 110, for a small screen.
    private let edge = 90.0

    func resize(_ next: CGSize) {
        guard next != size, next.width > 0, next.height > 0 else { return }
        if bees.isEmpty {
            bees = (0..<6).map { Bee(size: next, index: $0) }
        } else {
            let old = size
            func remap(_ point: CGPoint) -> CGPoint {
                CGPoint(x: point.x / old.width * next.width, y: point.y / old.height * next.height)
            }
            for index in bees.indices {
                bees[index].position = remap(bees[index].position)
                bees[index].home = remap(bees[index].home)
                bees[index].entrance = remap(bees[index].entrance)
            }
        }
        size = next
    }

    /// A fixed 60 Hz step, as on the phone; never catch up on a long pause.
    func advance(to date: Date) {
        if let previous { remainder += min(0.05, max(0, date.timeIntervalSince(previous))) }
        previous = date
        while remainder >= step {
            advance(step)
            remainder -= step
        }
    }

    private func advance(_ dt: Double) {
        elapsed += dt
        let tau = Double.pi * 2
        let positions = bees.map(\.position)
        for index in bees.indices {
            var bee = bees[index]
            let p = bee.position
            let seed = bee.seed
            var heading = bee.heading +
                (sin(elapsed * (0.27 + seed * 0.4) + seed * tau) + 0.6 * sin(elapsed * (0.13 + seed * 0.11) + seed * 7)) * 1.15 * dt
            func turnAt(_ value: Double, _ extent: Double) -> Double {
                value < edge ? 1 - value / edge : value > extent - edge ? -(1 - (extent - value) / edge) : 0
            }
            let turn = CGPoint(x: turnAt(p.x, size.width), y: turnAt(p.y, size.height))
            if turn != .zero {
                let delta = wrap(atan2(turn.y, turn.x) - heading + .pi * 3, tau) - .pi
                heading += delta * 3.2 * min(1, hypot(turn.x, turn.y)) * dt
            }
            let phase = wrap(elapsed * (0.24 + seed * 0.2) + seed * 5.37, 1)
            let burst = phase < 0.18 ? sin(phase / 0.18 * .pi) : 0
            let speed = max(
                58 * 0.46,
                58 * (1 + sin(elapsed * (0.42 + seed * 0.28) + seed * tau) * 0.32) + max(1, size.width) * 1.1 * burst
            )
            let target = CGPoint(x: cos(heading) * speed, y: sin(heading) * speed)
            var velocity = bee.velocity + (target - bee.velocity) * ((2.4 + 11 * burst) * dt)
            for (other, position) in positions.enumerated() where other != index {
                let delta = p - position
                let distance = hypot(delta.x, delta.y)
                if distance > 0, distance < 66 { velocity = velocity + delta * (1300 * (1 - distance / 66) / distance * dt) }
            }
            velocity = velocity + (bee.home - p) * (0.18 * dt)
            velocity = velocity + turn * (900 * dt)
            velocity = velocity * 0.97
            var next = p + velocity * dt
            if next.x < 0 || next.x > size.width { velocity.x *= -0.5 }
            if next.y < 0 || next.y > size.height { velocity.y *= -0.5 }
            next = CGPoint(x: min(max(next.x, 0), size.width), y: min(max(next.y, 0), size.height))
            bee.position = next
            bee.velocity = velocity
            bee.heading = heading
            if hypot(velocity.x, velocity.y) > 6 {
                let delta = wrap(atan2(velocity.y, velocity.x) + .pi / 2 - bee.rotation + .pi * 3, tau) - .pi
                bee.rotation += delta * 0.18
            }
            bees[index] = bee
        }
    }

    /// `value` modulo `by`, never negative.
    private func wrap(_ value: Double, _ by: Double) -> Double {
        let rest = value.truncatingRemainder(dividingBy: by)
        return rest < 0 ? rest + by : rest
    }
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
private func * (a: CGPoint, b: Double) -> CGPoint { CGPoint(x: a.x * b, y: a.y * b) }

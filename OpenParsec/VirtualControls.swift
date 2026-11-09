import SwiftUI
import ParsecSDK

// On-screen mouse-button row (L/M/R + side buttons) and virtual gamepad.
// Ported in spirit from the Android fork's MouseButtonRow / VirtualGamepad.

private func axis16(_ v: CGFloat) -> Int16 { Int16(max(-1, min(1, v)) * 32767) }

/// Button that reports press on touch-down and release on touch-up (hold = drag/click-hold).
struct HoldButton: View {
	let label: String
	var width: CGFloat = 44
	var height: CGFloat = 44
	var round = false
	let onChange: (Bool) -> Void
	@State private var down = false

	var body: some View {
		Text(label)
			.font(.system(size: 15, weight: .bold))
			.foregroundColor(.white)
			.frame(width: width, height: height)
			.background(down ? Color.accentColor : Color.black.opacity(0.55))
			.clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))
			.gesture(DragGesture(minimumDistance: 0)
				.onChanged { _ in if !down { down = true; onChange(true) } }
				.onEnded { _ in down = false; onChange(false) })
	}
}

// AnyShape is iOS 16+; tiny shim so the deployment target does not matter.
private struct AnyShape: Shape {
	private let make: (CGRect) -> Path
	init<S: Shape>(_ s: S) { make = { s.path(in: $0) } }
	func path(in rect: CGRect) -> Path { make(rect) }
}

struct MouseButtonRow: View {
	@AppStorage("mouseRowX") private var posX: Double = 0
	@AppStorage("mouseRowY") private var posY: Double = 0
	@State private var dragStart: CGSize? = nil

	private func btn(_ label: String, _ b: ParsecMouseButton) -> some View {
		HoldButton(label: label) { CParsec.sendMouseClickMessage(b, $0) }
	}

	var body: some View {
		VStack {
			Spacer()
			HStack(spacing: 6) {
				Image(systemName: "line.3.horizontal")
					.foregroundColor(.white)
					.frame(width: 28, height: 44)
					.contentShape(Rectangle())
					.gesture(DragGesture()
						.onChanged { v in
							let s = dragStart ?? CGSize(width: posX, height: posY)
							dragStart = s
							posX = Double(s.width + v.translation.width)
							posY = Double(s.height + v.translation.height)
						}
						.onEnded { _ in dragStart = nil })
				btn("◀", MOUSE_X1)
				btn("L", MOUSE_L)
				btn("M", MOUSE_MIDDLE)
				btn("R", MOUSE_R)
				btn("▶", MOUSE_X2)
			}
			.padding(6)
			.background(Color.black.opacity(0.35))
			.clipShape(RoundedRectangle(cornerRadius: 28))
			.offset(x: CGFloat(posX), y: CGFloat(posY))
			.padding(.bottom, 16)
		}
		.frame(maxWidth: .infinity)
	}
}

struct VirtualStick: View {
	let size: CGFloat
	let onChange: (CGFloat, CGFloat) -> Void // -1...1, screen-up is negative y
	@State private var knob: CGSize = .zero

	var body: some View {
		let r = size / 2
		ZStack {
			Circle().fill(Color.black.opacity(0.35))
			Circle().stroke(Color.white.opacity(0.5), lineWidth: 2)
			Circle().fill(Color.white.opacity(0.7))
				.frame(width: size * 0.4, height: size * 0.4)
				.offset(knob)
		}
		.frame(width: size, height: size)
		.contentShape(Circle())
		.gesture(DragGesture(minimumDistance: 0)
			.onChanged { v in
				var dx = v.location.x - r, dy = v.location.y - r
				let len = sqrt(dx * dx + dy * dy)
				if len > r { dx *= r / len; dy *= r / len }
				knob = CGSize(width: dx, height: dy)
				onChange(dx / r, dy / r)
			}
			.onEnded { _ in knob = .zero; onChange(0, 0) })
		.onDisappear { onChange(0, 0) }
	}
}

struct VirtualGamepad: View {
	private func pad(_ b: ParsecGamepadButton, _ pressed: Bool) {
		CParsec.sendGameControllerButtonMessage(controllerId: 1, b, pressed: pressed)
	}
	private func axis(_ a: ParsecGamepadAxis, _ v: Int16) {
		CParsec.sendGameControllerAxisMessage(controllerId: 1, a, v)
	}
	private func b(_ l: String, _ g: ParsecGamepadButton, round: Bool = true, w: CGFloat = 44) -> some View {
		HoldButton(label: l, width: w, height: 44, round: round) { pad(g, $0) }
	}
	private func trig(_ l: String, _ a: ParsecGamepadAxis) -> some View {
		HoldButton(label: l, width: 56, height: 36) { axis(a, $0 ? 32767 : 0) }
	}

	var body: some View {
		ZStack {
			// shoulders / triggers
			VStack {
				HStack {
					VStack(spacing: 6) { trig("LT", GAMEPAD_AXIS_TRIGGERL); b("LB", GAMEPAD_BUTTON_LSHOULDER, round: false, w: 56) }
					Spacer()
					VStack(spacing: 6) { trig("RT", GAMEPAD_AXIS_TRIGGERR); b("RB", GAMEPAD_BUTTON_RSHOULDER, round: false, w: 56) }
				}
				Spacer()
			}
			// left side: dpad + left stick
			VStack {
				Spacer()
				HStack {
					VStack(spacing: 8) {
						HStack(spacing: 4) {
							b("←", GAMEPAD_BUTTON_DPAD_LEFT); b("↑", GAMEPAD_BUTTON_DPAD_UP)
							b("↓", GAMEPAD_BUTTON_DPAD_DOWN); b("→", GAMEPAD_BUTTON_DPAD_RIGHT)
						}
						VirtualStick(size: 120) { x, y in axis(GAMEPAD_AXIS_LX, axis16(x)); axis(GAMEPAD_AXIS_LY, axis16(y)) }
					}
					Spacer()
				}
			}
			// center: back / start
			VStack {
				Spacer()
				HStack(spacing: 12) {
					b("BK", GAMEPAD_BUTTON_BACK, round: false, w: 52)
					b("ST", GAMEPAD_BUTTON_START, round: false, w: 52)
				}
			}
			// right side: face buttons + right stick
			VStack {
				Spacer()
				HStack {
					Spacer()
					VStack(spacing: 8) {
						VStack(spacing: 4) {
							b("Y", GAMEPAD_BUTTON_Y)
							HStack(spacing: 30) { b("X", GAMEPAD_BUTTON_X); b("B", GAMEPAD_BUTTON_B) }
							b("A", GAMEPAD_BUTTON_A)
						}
						VirtualStick(size: 120) { x, y in axis(GAMEPAD_AXIS_RX, axis16(x)); axis(GAMEPAD_AXIS_RY, axis16(y)) }
					}
				}
			}
		}
		.padding(16)
	}
}

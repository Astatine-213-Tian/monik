import SwiftUI

/// A native segmented time editor with room after AM/PM and click-away dismissal.
struct TimeField: View {
    @Binding var selection: Date

    var body: some View {
        TimeFieldEditor(selection: $selection)
            .fixedSize()
            // The native editor already includes a leading text inset.
            .padding(.leading, -0.5)
            .padding(.trailing, 4.5)
            .padding(.top, 3)
            .padding(.bottom, 1)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct TimeFieldEditor: NSViewRepresentable {
    @Binding var selection: Date

    func makeNSView(context: Context) -> TimePicker {
        let picker = TimePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.cell?.isEditable = true
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: TimePicker, context: Context) {
        context.coordinator.selection = $selection
        if picker.dateValue != selection {
            picker.dateValue = selection
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    static func dismantleNSView(_ picker: TimePicker, coordinator: Coordinator) {
        picker.stopMonitoring()
    }

    final class Coordinator: NSObject {
        var selection: Binding<Date>

        init(selection: Binding<Date>) { self.selection = selection }

        @objc func changed(_ sender: NSDatePicker) {
            selection.wrappedValue = sender.dateValue
        }
    }
}

private final class TimePicker: NSDatePicker {
    private var mouseMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dismissIfOutside(event)
            }
            return event
        }
    }

    private func dismissIfOutside(_ event: NSEvent) {
        guard let window, event.window === window,
              let responder = window.firstResponder as? NSView,
              responder === self || responder.isDescendant(of: self) || responder === currentEditor(),
              !bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        // Let the click continue so another field or control can take focus.
        window.makeFirstResponder(nil)
    }

    func stopMonitoring() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }
}

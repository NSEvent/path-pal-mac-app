import SwiftUI

struct OnboardingView: View {
    @State private var isAccessibilityGranted = PermissionsService.shared.isAccessibilityGranted
    @State private var isAutomationGranted = false
    @State private var isFullDiskAccessGranted = PermissionsService.shared.isFullDiskAccessGranted
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0.0
    let onComplete: () -> Void

    private var grantedCount: Int {
        [isAccessibilityGranted, isAutomationGranted, isFullDiskAccessGranted].filter { $0 }.count
    }

    var body: some View {
        VStack(spacing: 28) {
            // App icon with entrance animation
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .blue.opacity(0.25), radius: 12, y: 4)
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        iconScale = 1.0
                    }
                    withAnimation(.easeOut(duration: 0.5)) {
                        iconOpacity = 1.0
                    }
                }

            VStack(spacing: 8) {
                Text("Welcome to PathPal")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Enhances macOS Open/Save dialogs with quick\nfolder navigation and Finder integration.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            // Step counter
            Text("Step \(min(grantedCount + 1, 3)) of 3")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.quaternary)
                )

            // Permission steps as a vertical timeline
            VStack(spacing: 0) {
                permissionStep(
                    number: 1,
                    title: "Accessibility",
                    description: "Detect Open/Save dialogs and navigate them",
                    isGranted: isAccessibilityGranted,
                    isLast: false,
                    action: {
                        PermissionsService.shared.requestAccessibility()
                        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                            if PermissionsService.shared.isAccessibilityGranted {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    isAccessibilityGranted = true
                                }
                                timer.invalidate()
                            }
                        }
                    }
                )

                permissionStep(
                    number: 2,
                    title: "Automation (Finder)",
                    description: "Read Finder window paths and navigate",
                    isGranted: isAutomationGranted,
                    isLast: false,
                    action: {
                        let granted = PermissionsService.shared.requestAndCheckAutomationPermission()
                        if granted {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                isAutomationGranted = true
                            }
                        } else {
                            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                                if PermissionsService.shared.requestAndCheckAutomationPermission() {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        isAutomationGranted = true
                                    }
                                    timer.invalidate()
                                }
                            }
                        }
                    }
                )

                permissionStep(
                    number: 3,
                    title: "Full Disk Access",
                    description: "Optional — read Finder sidebar favorites",
                    isGranted: isFullDiskAccessGranted,
                    isLast: true,
                    action: {
                        PermissionsService.shared.openFullDiskAccessPreferences()
                        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
                            if PermissionsService.shared.isFullDiskAccessGranted {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    isFullDiskAccessGranted = true
                                }
                                timer.invalidate()
                            }
                        }
                    }
                )
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    )
            }

            Button {
                SettingsService.shared.hasCompletedOnboarding = true
                onComplete()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isAccessibilityGranted)
        }
        .padding(40)
        .frame(width: 500, height: 560)
        .onAppear {
            isAutomationGranted = PermissionsService.shared.requestAndCheckAutomationPermission()
        }
    }

    // MARK: - Permission Step with Timeline

    private func permissionStep(
        number: Int,
        title: String,
        description: String,
        isGranted: Bool,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Timeline indicator
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isGranted ? AnyShapeStyle(Color.green) : AnyShapeStyle(.quaternary))
                        .frame(width: 28, height: 28)

                    if isGranted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("\(number)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if !isLast {
                    Rectangle()
                        .fill(isGranted ? AnyShapeStyle(Color.green.opacity(0.3)) : AnyShapeStyle(.quaternary))
                        .frame(width: 2, height: 36)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.body)
                        .fontWeight(.semibold)
                    Spacer()
                    if isGranted {
                        Text("Granted")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant") { action() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
}

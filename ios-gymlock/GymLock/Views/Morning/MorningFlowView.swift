import SwiftUI

/// The router for a live morning.
///
/// Every screen shown here is chosen from `GymSessionCoordinator.route`, which
/// is itself derived from the single session state. There is no navigation stack
/// and no local "which screen am I on" flag, because either would be a second
/// source of truth able to disagree with the session — and disagreeing with the
/// session is exactly how a flow like this ends up showing a countdown that has
/// already expired.
struct MorningFlowView: View {
    @Environment(AppStore.self) private var store
    @Environment(GymSessionCoordinator.self) private var coordinator

    @State private var verifier: any WorkoutVerificationProviding = WorkoutVerificationFactory.make()

    private var session: GymSession? { coordinator.session }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            if let session, let route = coordinator.route {
                screen(for: route, session: session)
                    .transition(.opacity)
                    .id(route)
            }
        }
        .animation(Theme.settle, value: coordinator.route)
        // The nudge is a sheet rather than a route: the countdown underneath is
        // still the truth, and the user should be able to dismiss back onto it.
        .sheet(isPresented: nudgeBinding) {
            if let session {
                StillGettingReadyView(
                    session: session,
                    onLeaving: {
                        coordinator.dismissPreparationNudge()
                        coordinator.markDeparted(detected: false)
                    },
                    onExtend: { coordinator.extendWindow() },
                    onQuickWorkout: {
                        coordinator.dismissPreparationNudge()
                        coordinator.offerQuickWorkout()
                    },
                    onDismiss: { coordinator.dismissPreparationNudge() }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var nudgeBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isShowingPreparationNudge },
            set: { if !$0 { coordinator.dismissPreparationNudge() } }
        )
    }

    // MARK: - Routing

    @ViewBuilder
    private func screen(for route: MorningRoute, session: GymSession) -> some View {
        switch route {
        case .decision:
            AlarmFiredView(
                alarmTime: session.alarmTime,
                onGoing: { coordinator.commitToGoing() },
                onMoveTime: { coordinator.moveTodaysTime(by: $0) },
                onCantToday: { coordinator.beginCantToday() }
            )

        case .mission:
            ActivationMissionView(
                session: session,
                onComplete: { coordinator.completeMission() },
                onChoose: { coordinator.chooseMission($0) },
                onReroll: { coordinator.rerollMission(capabilities: $0) },
                onSkip: { coordinator.skipMission() },
                onCancel: { coordinator.beginCantToday() }
            )

        case .countdown:
            GymWindowView(
                session: session,
                lockedApps: store.profile.orderedDistractingApps,
                onDeparted: { coordinator.markDeparted(detected: false) },
                onEnd: { coordinator.beginCantToday() }
            )

        case .departed:
            DepartedView(session: session) {
                coordinator.acknowledgeDeparture()
            }

        case .plansChanged:
            PlansChangedView(
                onStillGoing: { coordinator.grantGrace() },
                onQuickWorkout: { coordinator.offerQuickWorkout() },
                onCantToday: { coordinator.beginCantToday() }
            )

        case .quickWorkoutPicker:
            QuickWorkoutView(
                onStart: { coordinator.startQuickWorkout(minutes: $0) },
                onBack: { coordinator.leaveQuickWorkoutPicker() }
            )

        case .quickWorkoutActive:
            QuickWorkoutActiveView(
                session: session,
                verifier: verifier,
                onFinish: { coordinator.finishQuickWorkout(completed: $0) }
            )

        case .momentumSaved:
            MomentumSavedView(
                momentumStreak: store.log.momentumStreak,
                recentMomentum: store.log.recentMomentum(),
                onKeepGoing: { coordinator.acknowledgeResult() },
                onDone: { coordinator.acknowledgeResult() }
            )

        case .cantToday:
            CantTodayView(
                hasEasySkipRemaining: coordinator.hasEasySkipRemaining,
                skipsUsed: coordinator.easySkipsUsed,
                allowance: coordinator.easySkipAllowance,
                isComebackModeOn: store.profile.comebackModeEnabled,
                onReschedule: { coordinator.resolveCantToday(.rescheduledWithin24h) },
                onQuickWorkout: { coordinator.resolveCantToday(.quickWorkout) },
                onTakeTheDayOff: { coordinator.resolveCantToday(.tookTheDayOff) },
                onBack: { coordinator.endSession() }
            )

        case .confirmingArrival:
            ConfirmingArrivalView(
                session: session,
                gymName: store.primaryGym?.name,
                onSkipToTrouble: { coordinator.reportArrivalTroubleManually() }
            )

        case .arrivalTrouble:
            ArrivalTroubleView(
                gymName: store.primaryGym?.name,
                onRetry: { coordinator.retryArrival() },
                onConfirmManually: { coordinator.confirmArrivalManually() },
                onQuickWorkout: { coordinator.offerQuickWorkout() },
                onRelease: { coordinator.releaseAfterArrivalTrouble() }
            )

        case .gymSuccess:
            GymArrivedView(
                session: session,
                gymName: store.primaryGym?.name,
                momentumStreak: store.log.momentumStreak,
                gymVisitsThisMonth: store.log.verifiedGymVisitsThisMonth,
                shieldCapability: coordinator.shieldCapability,
                onDone: { coordinator.acknowledgeResult() }
            )
        }
    }
}



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
    @Environment(ProgressPhotoStore.self) private var photos: ProgressPhotoStore?

    /// Raised by the two success screens. The morning flow is itself a
    /// full-screen cover, so the editor is presented from here rather than
    /// from the tab shell underneath it, which is not on screen.
    @State private var shareOrigin: ShareOrigin?

    /// The session whose trip page is on screen right now. Arrival only plays
    /// the trip's "verified" finale when the user was looking at the trip.
    @State private var tripShownFor: UUID?
    /// The session whose verified finale has finished, so the arrival screen
    /// takes over and stays.
    @State private var finaleDoneFor: UUID?

    private var session: GymSession? { coordinator.session }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            if let session, let route = coordinator.route {
                screen(for: route, session: session)
                    .transition(.opacity)
                    // The trip is one page across its routes, so it keeps one
                    // identity and changes in place instead of being rebuilt.
                    .id(screenKey(for: route, session: session))
            }
        }
        .animation(Theme.settle, value: coordinator.route)
        .storyEditor(origin: $shareOrigin)
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

    /// Countdown, departure and the arrival check are one trip page when the
    /// user has a gym to draw a route to. Without one, the older screens stay.
    private func usesTrip(_ route: MorningRoute, session: GymSession) -> Bool {
        guard store.primaryGym != nil else { return false }
        switch route {
        case .countdown, .departed, .confirmingArrival:
            return true
        case .gymSuccess:
            return tripShownFor == session.id && finaleDoneFor != session.id
        default:
            return false
        }
    }

    private func screenKey(for route: MorningRoute, session: GymSession) -> String {
        usesTrip(route, session: session) ? "trip" : String(describing: route)
    }

    @ViewBuilder
    private func screen(for route: MorningRoute, session: GymSession) -> some View {
        if usesTrip(route, session: session), let gym = store.primaryGym {
            tripScreen(route: route, session: session, gym: gym)
        } else {
            routedScreen(for: route, session: session)
        }
    }

    private func tripScreen(route: MorningRoute, session: GymSession, gym: GymLocation) -> some View {
        let sessionID = session.id
        return TripView(
            session: session,
            route: route,
            gym: gym,
            onLeft: { coordinator.markDeparted(detected: false) },
            onEnd: { coordinator.beginCantToday() },
            onTrouble: { coordinator.reportArrivalTroubleManually() },
            onAcknowledgeDeparture: { coordinator.acknowledgeDeparture() },
            onShown: { tripShownFor = sessionID },
            onHidden: { if tripShownFor == sessionID { tripShownFor = nil } },
            onFinaleDone: { finaleDoneFor = sessionID }
        )
    }

    @ViewBuilder
    private func routedScreen(for route: MorningRoute, session: GymSession) -> some View {
        switch route {
        case .decision:
            AlarmFiredView(
                session: session,
                onGoing: { coordinator.commitToGoing() },
                onSnooze: { coordinator.snooze() },
                runningLateOptions: coordinator.runningLateOptions,
                onRunningLate: { coordinator.runningLate(by: $0) },
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
                session: session,
                context: .windowClosed,
                onStillGoing: { coordinator.grantGrace() },
                onQuickWorkout: { coordinator.offerQuickWorkout() },
                onCantToday: { coordinator.beginCantToday() }
            )

        case .quickWorkoutPicker:
            QuickWorkoutView(
                homeWorkoutsUsed: coordinator.homeWorkoutsUsedThisMonth,
                isAtCap: coordinator.homeWorkoutCapReached,
                onStart: { coordinator.startQuickWorkout(minutes: $0) },
                onBack: { coordinator.leaveQuickWorkoutPicker() }
            )

        case .quickWorkoutActive:
            QuickWorkoutActiveView(
                session: session,
                onFinish: { coordinator.finishQuickWorkout(completed: $0) }
            )

        case .homeWorkoutProof:
            HomeWorkoutProofView(
                photos: photos,
                onDone: { coordinator.acknowledgeResult() }
            )

        case .momentumSaved:
            MomentumSavedView(
                momentumWeeks: store.streak.weeks,
                recentMomentum: store.log.recentMomentum(),
                onKeepGoing: { coordinator.acknowledgeResult() },
                onDone: { coordinator.acknowledgeResult() },
                voice: SessionVoice(session: session),
                onShare: { shareOrigin = .session(day: session.day) }
            )

        case .cantToday:
            CantTodayView(
                voice: SessionVoice(session: session),
                plan: coordinator.skipScreen,
                choices: coordinator.rescheduleChoices,
                defaultTimeFor: { coordinator.rescheduleDefaultTime(for: $0) },
                isTimeAvailable: { coordinator.isRescheduleTimeAvailable($1, on: $0) },
                isComebackModeOn: store.profile.comebackModeEnabled,
                onReschedule: { coordinator.reschedule(to: $0, at: $1) },
                onHomeWorkout: { coordinator.resolveCantToday(.homeWorkout) },
                onSkip: { coordinator.resolveCantToday(.skip) },
                onBack: { coordinator.endSession() },
                startsOnPicker: coordinator.wantsReschedulePicker,
                onPickerShown: { coordinator.consumeReschedulePicker() }
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
                momentumWeeks: store.streak.weeks,
                gymVisitsThisMonth: store.log.verifiedGymVisitsThisMonth,
                shieldCapability: coordinator.shieldCapability,
                voice: SessionVoice(session: session),
                onDone: { coordinator.acknowledgeResult() },
                onShare: { shareOrigin = .session(day: session.day) }
            )
        }
    }
}



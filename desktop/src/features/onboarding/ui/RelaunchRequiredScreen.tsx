import { RecoveryScreen } from "./RecoveryScreen";

export function RelaunchRequiredScreen() {
  return (
    <RecoveryScreen
      testId="relaunch-required"
      title="Restart Sion to finish recovery"
      body="Your identity was updated. Sion needs to restart so syncing and agents run under it."
    />
  );
}

import { Navigate, Route, Routes } from "react-router-dom";
import { useSession } from "./hooks/useSession";
import { Landing } from "./screens/Landing";
import { AppShell } from "./components/AppShell";
import { RecordScreen } from "./screens/RecordScreen";
import { StatsScreen } from "./screens/StatsScreen";
import { MindsScreen } from "./screens/MindsScreen";
import { SettingsScreen } from "./screens/SettingsScreen";

export function App() {
  const session = useSession();

  if (!session) {
    return (
      <Routes>
        <Route path="/" element={<Landing />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    );
  }

  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route index element={<RecordScreen />} />
        <Route path="stats" element={<StatsScreen />} />
        <Route path="minds" element={<MindsScreen />} />
        <Route path="settings" element={<SettingsScreen />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}

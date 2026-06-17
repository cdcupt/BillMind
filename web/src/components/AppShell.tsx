import { NavLink, Outlet } from "react-router-dom";
import "./shell.css";

const NAV = [
  { to: "/", label: "Record", end: true },
  { to: "/stats", label: "Stats", end: false },
  { to: "/minds", label: "Minds", end: false },
  { to: "/settings", label: "Settings", end: false },
] as const;

/** Authenticated frame: a slim header + the four-section nav, content in the
 *  outlet. The nav is a bottom bar on phones, a left rail on wider screens. */
export function AppShell() {
  return (
    <div className="shell">
      <header className="shell__head">
        <span className="shell__mark">
          BillOwl<span className="shell__mark-dot">.</span>
        </span>
      </header>

      <main className="shell__content">
        <Outlet />
      </main>

      <nav className="shell__nav" aria-label="Sections">
        {NAV.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            className={({ isActive }) =>
              `shell__tab${isActive ? " shell__tab--active" : ""}`
            }
          >
            {item.label}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}

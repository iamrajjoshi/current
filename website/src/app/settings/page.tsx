import { Footer } from "@/components/Footer";
import { NavBar } from "@/components/NavBar";
import { completeConfigSnippet, configLocations, settings } from "@/lib/settings";

const groupedSettings = settings.reduce<Record<string, typeof settings>>((groups, setting) => {
  groups[setting.category] = groups[setting.category] ?? [];
  groups[setting.category].push(setting);
  return groups;
}, {});

export default function SettingsPage() {
  return (
    <>
      <NavBar />
      <main className="settings-page">
        <section className="settings-hero">
          <div className="shell settings-hero-grid">
            <div>
              <p className="eyebrow">Settings</p>
              <h1>Settings</h1>
              <p className="lede">
                Current can read preferences from a config.current file. Defaults are built in, so you only add the keys you want to change.
              </p>
            </div>
            <div className="settings-location-panel" aria-label="Current config search order">
              <p className="panel-kicker">Search order</p>
              <ol>
                {configLocations.map((location) => (
                  <li key={location}>
                    <code>{location}</code>
                  </li>
                ))}
              </ol>
            </div>
          </div>
        </section>

        <section className="settings-reference">
          <div className="shell">
            {Object.entries(groupedSettings).map(([category, categorySettings]) => (
              <section className="settings-group" key={category}>
                <div className="settings-group-heading">
                  <p className="eyebrow">{category}</p>
                  <h2>{category}</h2>
                </div>
                <div className="settings-table-wrap">
                  <table className="settings-table">
                    <thead>
                      <tr>
                        <th>Key</th>
                        <th>Default</th>
                        <th>Accepted values</th>
                        <th>Purpose</th>
                      </tr>
                    </thead>
                    <tbody>
                      {categorySettings.map((setting) => (
                        <tr key={setting.key}>
                          <td data-label="Key">
                            <code>{setting.key}</code>
                            <span>{setting.example}</span>
                          </td>
                          <td data-label="Default">{setting.defaultValue}</td>
                          <td data-label="Accepted values">{setting.acceptedValues}</td>
                          <td data-label="Purpose">{setting.description}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </section>
            ))}
          </div>
        </section>

        <section className="settings-snippet">
          <div className="shell snippet-grid">
            <div>
              <p className="eyebrow">config.current</p>
              <h2>Complete starter file</h2>
              <p>
                Empty values reset to Current defaults. Whole-line comments and blank lines are ignored. Included files are parsed after the containing file, so machine-specific overrides can stay separate.
              </p>
            </div>
            <pre className="code-panel"><code>{completeConfigSnippet}</code></pre>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}

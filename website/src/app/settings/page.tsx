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
              <h1>Settings</h1>
              <p className="lede">
                Edit <code>config.current</code> to change Current&apos;s preferences. Add only the settings you want to override.
              </p>
            </div>
            <div className="settings-location-panel" aria-label="Current config search order">
              <p className="panel-kicker">Current reads the first file it finds:</p>
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
              <h2>Example config.current</h2>
              <p>
                Empty values reset a setting to its default. Blank lines and whole-line comments are ignored. Included files are read afterward and can override earlier values.
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

import Link from "next/link";
import { highlightedSettings } from "@/lib/settings";

export function ConfigTeaser() {
  return (
    <section className="section config-teaser">
      <div className="shell config-grid">
        <div>
          <h2>Adjust the writing surface.</h2>
          <p>
            Set the editor font, text size, line height and column width in <code>config.current</code>. The same file controls your notes folder, history range and autosave delay.
          </p>
          <Link className="text-link" href="/settings/">
            View the settings reference
          </Link>
        </div>
        <div className="settings-preview">
          {highlightedSettings.map((setting) => (
            <div className="setting-preview-row" key={setting.key}>
              <code>{setting.key}</code>
              <span>{setting.defaultValue}</span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

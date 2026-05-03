import Link from "next/link";
import { highlightedSettings } from "@/lib/settings";

export function ConfigTeaser() {
  return (
    <section className="section config-teaser">
      <div className="shell config-grid">
        <div>
          <p className="eyebrow">Configuration</p>
          <h2>Preferences live in config.current.</h2>
          <p>
            Use a small config file to change the notes folder, editor font, text size, line height, writing width, history range, and autosave delay.
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

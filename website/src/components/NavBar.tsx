import { Github, Settings } from "lucide-react";
import Link from "next/link";
import { basePath } from "@/lib/base-path";

export function NavBar() {
  return (
    <header className="site-nav">
      <div className="site-nav-inner">
        <Link href="/" className="brand-link" aria-label="Current home">
          <img src={`${basePath}/current-icon.png`} alt="" width={28} height={28} />
          <span>Current</span>
        </Link>
        <nav aria-label="Primary navigation">
          <Link href="/#features">Features</Link>
          <Link href="/#storage">Storage</Link>
          <Link href="/settings/">
            <Settings size={16} aria-hidden="true" />
            Settings
          </Link>
          <a href="https://github.com/iamrajjoshi/current" rel="noreferrer">
            <Github size={16} aria-hidden="true" />
            GitHub
          </a>
        </nav>
      </div>
    </header>
  );
}

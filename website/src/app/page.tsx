import { ConfigTeaser } from "@/components/ConfigTeaser";
import { FeatureGrid } from "@/components/FeatureGrid";
import { Footer } from "@/components/Footer";
import { HeroStreamScene } from "@/components/HeroStreamScene";
import { InstallCTA } from "@/components/InstallCTA";
import { NavBar } from "@/components/NavBar";
import { RoadmapSection } from "@/components/RoadmapSection";
import { StorageSection } from "@/components/StorageSection";

export default function Home() {
  return (
    <>
      <NavBar />
      <main>
        <HeroStreamScene />
        <FeatureGrid />
        <StorageSection />
        <ConfigTeaser />
        <RoadmapSection />
        <InstallCTA />
      </main>
      <Footer />
    </>
  );
}

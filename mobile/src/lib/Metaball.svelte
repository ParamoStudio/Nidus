<script>
  /**
   * The living Nidus metaball, ported from the app's MetaballView.
   *
   * Same idea, same technique: a central mass plus satellites that orbit, drift, merge and split,
   * all blurred and then alpha-thresholded so they fuse into ONE gooey silhouette with visible necks.
   * In SwiftUI that's `.blur` + `.alphaThreshold`; on the web it's feGaussianBlur + feColorMatrix.
   *
   * It has to actually MOVE — a frozen blob reads as a broken image, not as the app's mark.
   */
  let { size = 96 } = $props();

  // Deterministic-ish blobs, in the spirit of the avatar mode: few, sizeable, swinging far out.
  const blobs = [
    { orbit: 0.30, speed: 0.42, phase: 0.0, yFreq: 1.10, r: 0.125, pulse: 0.05 },
    { orbit: 0.26, speed: -0.55, phase: 2.1, yFreq: 0.85, r: 0.115, pulse: 0.04 },
    { orbit: 0.34, speed: 0.31, phase: 4.0, yFreq: 1.25, r: 0.105, pulse: 0.05 },
  ];

  let t = $state(0);
  $effect(() => {
    let raf;
    const start = performance.now();
    const tick = (now) => {
      t = (now - start) / 1000;
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  });

  // A slow whole-body breath, so even the still moments feel alive.
  const breath = $derived(1 + 0.03 * Math.sin(t * 0.9));
  const centre = $derived({
    x: 50 + 2.4 * Math.sin(t * 0.23),
    y: 50 + 2.0 * Math.cos(t * 0.19),
    r: 17.5 * breath,
  });
  const sats = $derived(
    blobs.map((b) => ({
      x: centre.x + b.orbit * 100 * Math.cos(t * b.speed + b.phase),
      y: centre.y + b.orbit * 100 * 0.82 * Math.sin(t * b.speed * b.yFreq + b.phase),
      r: (b.r * 100 * (1 + b.pulse * Math.sin(t * 1.3 + b.phase))) * breath,
    }))
  );
</script>

<svg class="metaball" viewBox="0 0 100 100" width={size} height={size} aria-hidden="true">
  <defs>
    <filter id="nidus-goo">
      <feGaussianBlur in="SourceGraphic" stdDeviation="5.5" result="blur" />
      <!-- The alpha threshold: what turns overlapping blurred circles into one gooey mass with necks. -->
      <feColorMatrix in="blur" mode="matrix"
        values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 26 -11" result="goo" />
    </filter>
    <!-- Themed: near-white in dark, near-black in light — the same contrast rule MetaballView uses. -->
    <radialGradient id="nidus-sheen" cx="36%" cy="30%">
      <stop offset="0%" stop-color="var(--blob-hi)" />
      <stop offset="70%" stop-color="var(--blob-mid)" />
      <stop offset="100%" stop-color="var(--blob-lo)" />
    </radialGradient>
  </defs>
  <g filter="url(#nidus-goo)" fill="url(#nidus-sheen)">
    <circle cx={centre.x} cy={centre.y} r={centre.r} />
    {#each sats as s}
      <circle cx={s.x} cy={s.y} r={s.r} />
    {/each}
  </g>
</svg>

<style>
  .metaball { display: block; filter: drop-shadow(0 8px 30px var(--blob-glow)); }
</style>

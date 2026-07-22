<script>
  /**
   * A project's real icon, in the app's glass circle (SphereView).
   *
   * Nidus renders the glyph itself and sends it down as a white silhouette, so metaballs, Bauhaus
   * glyphs, bundled icons and imported logos all arrive looking exactly as they do on the desktop.
   * We paint it as a MASK rather than an image: the silhouette takes `currentColor`, which is how the
   * same asset reads correctly in both light and dark appearance.
   *
   * The circle itself is almost entirely transparent — a faint edge and a little glare, per the app.
   * No icon yet (an older Nidus, or a sync that hasn't happened) falls back to the initial.
   */
  let { project, size = 40, ring = true } = $props();

  const initial = $derived((project?.name || "?").trim().charAt(0).toUpperCase());
</script>

<span class="icon" class:ring style="--d:{size}px">
  {#if project?.icon}
    <span class="glyph" style='-webkit-mask-image:url("{project.icon}");mask-image:url("{project.icon}")'></span>
  {:else}
    <span class="initial">{initial}</span>
  {/if}
</span>

<style>
  .icon {
    width: var(--d);
    height: var(--d);
    flex: none;
    display: grid;
    place-items: center;
    position: relative;
    border-radius: 50%;
  }
  .icon.ring {
    border: 1px solid var(--sphere-edge);
  }
  /* The small top glare that keeps a transparent circle catching the light. */
  .icon.ring::before {
    content: "";
    position: absolute;
    inset: 10%;
    border-radius: 50%;
    background: linear-gradient(to bottom, var(--sphere-glare), transparent 48%);
    /* Blur with the circle, or a big sphere gets a hard-edged cap instead of a soft glint. */
    filter: blur(calc(var(--d) * 0.06));
    opacity: 0.75;
    pointer-events: none;
  }
  .glyph {
    width: 62%;
    height: 62%;
    background: currentColor;
    -webkit-mask-size: contain;
    mask-size: contain;
    -webkit-mask-position: center;
    mask-position: center;
    -webkit-mask-repeat: no-repeat;
    mask-repeat: no-repeat;
  }
  .initial {
    font-size: calc(var(--d) * 0.38);
    font-weight: 600;
    color: var(--dim);
  }
</style>

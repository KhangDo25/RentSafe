function App() {
  return (
    <main className="page-shell">
      <nav className="topbar" aria-label="Main navigation">
        <a className="brand" href="#home" aria-label="RentSafe home">
          <span className="brand-mark" aria-hidden="true">R</span>
          <span>RentSafe</span>
        </a>
        <span className="topbar-note">Rental operations, made clear</span>
      </nav>

      <section className="hero" id="home">
        <div className="hero-copy">
          <p className="eyebrow"><span /> Built for the things you put to work</p>
          <h1>Keep every<br />rental <em>in motion.</em></h1>
          <p className="intro">
            A calmer way to manage vehicles, equipment, and machinery.
            RentSafe is the foundation for keeping your rental operation organized.
          </p>
          <a className="cta" href="#about">Explore RentSafe <span aria-hidden="true">↗</span></a>
          <p className="status"><span className="status-dot" /> Project foundation · Phase 1</p>
        </div>

        <div className="hero-art" aria-label="Illustration of a utility vehicle on a road">
          <div className="sun" />
          <div className="hill hill-back" />
          <div className="hill hill-front" />
          <div className="road"><span /></div>
          <div className="vehicle">
            <div className="vehicle-cab"><span /></div>
            <div className="vehicle-bed" />
            <div className="vehicle-body" />
            <div className="wheel wheel-left" /><div className="wheel wheel-right" />
          </div>
          <div className="art-label"><span className="label-icon">↗</span><span>Ready for<br /><strong>what’s next</strong></span></div>
          <div className="art-caption">THE RENTAL ASSET, REIMAGINED</div>
        </div>
      </section>

      <section className="about" id="about">
        <div><span className="section-index">01 / A clearer view</span><h2>Make room for<br />better work.</h2></div>
        <p>One dependable place to build the habits, tools, and visibility that help a rental business run smoothly. This is the starting point.</p>
        <span className="about-arrow" aria-hidden="true">↘</span>
      </section>

      <footer><span>© 2026 RentSafe</span><span>Built for the long haul.</span></footer>
    </main>
  )
}

export default App

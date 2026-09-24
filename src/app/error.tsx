"use client";
export default function ErrorPage({ reset }: { reset: () => void }) { return <main className="status-page"><p className="eyebrow">CARRIER CONFIGURATION</p><h1>We couldn’t load your workspace</h1><p>Please try again. If the problem continues, contact your administrator.</p><button onClick={reset}>Try again</button><a className="back" href="/login">Return to sign in</a></main>; }

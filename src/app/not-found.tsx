import Link from "next/link";
export default function NotFound() { return <main className="status-page"><h1>Carrier unavailable</h1><p>This carrier does not exist or is not available to your account.</p><Link className="back" href="/carriers">Return to carrier selection</Link></main>; }

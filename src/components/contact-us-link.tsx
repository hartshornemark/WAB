const contactAddress = "administrator@waqiqa.com";

export function ContactUsLink({ className = "" }: { className?: string }) {
  return <a className={`contact-us-link${className ? ` ${className}` : ""}`} href={`mailto:${contactAddress}`}>
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M3.75 5.75h16.5v12.5H3.75z" />
      <path d="m4.5 6.5 7.5 6 7.5-6" />
    </svg>
    <span><strong>CONTACT US</strong><small>{contactAddress}</small></span>
  </a>;
}

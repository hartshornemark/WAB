import Image from "next/image";
import { redirect } from "next/navigation";
import { services } from "@/composition/services";
import { SignInForm } from "@/components/sign-in-form";
export default async function Login() {
  if (await (await services()).currentUser()) redirect("/carriers");
  return <main className="login-layout"><section className="intro">
    <div className="brand"><Image src="/brand/wb-logo.png" alt="W/B" width={384} height={633} className="login-logo" preload unoptimized /> CARRIER CONFIGURATION</div>
    <div className="intro-copy"><p className="eyebrow">THE FOUNDATION FOR EVERY FLIGHT</p><h1>Your fleet.<br />Your standards.<br /><span>One workspace.</span></h1><p>A focused home for your airline’s configuration, from carrier records to aircraft details.</p></div>
    <div className="intro-footer">CARRIER OPERATIONS <span>01 / ACCESS</span></div>
  </section><section className="login-panel"><div className="login-card"><p className="eyebrow">WELCOME BACK</p><h2>Sign in to your workspace</h2><p className="muted">Use your assigned account to access your carriers.</p><SignInForm /><p className="help">Need access or help signing in?<br />Contact your organisation administrator.</p></div></section></main>;
}

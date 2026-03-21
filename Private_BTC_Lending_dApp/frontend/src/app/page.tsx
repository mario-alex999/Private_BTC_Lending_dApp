import { BorrowDashboard } from '@/components/BorrowDashboard';

export default function Home() {
  return (
    <main className="shell">
      <section className="hero">
        <p className="eyebrow">Private BTC Lending</p>
        <h1>Borrow Against Bitcoin With Proof-Based Privacy</h1>
        <p>
          Verify BTC collateral trustlessly, choose your target LTV, and borrow stablecoins with
          optional local zero-knowledge proving.
        </p>
      </section>
      <BorrowDashboard />
    </main>
  );
}

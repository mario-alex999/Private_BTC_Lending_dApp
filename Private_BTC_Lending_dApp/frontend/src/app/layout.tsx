import type { Metadata } from 'next';
import { JetBrains_Mono, Space_Grotesk } from 'next/font/google';
import './globals.css';
import { Providers } from './providers';

const headline = Space_Grotesk({
  variable: '--font-headline',
  subsets: ['latin'],
  weight: ['400', '500', '700']
});

const mono = JetBrains_Mono({
  variable: '--font-mono',
  subsets: ['latin'],
  weight: ['400', '600']
});

export const metadata: Metadata = {
  title: 'Private BTC Lending | Borrow',
  description: 'Private lending with Bitcoin collateral on Starknet'
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className={`${headline.variable} ${mono.variable}`}>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}

import type { ReactNode } from 'react'
import 'nextra-theme-docs/style.css'
import { Layout } from 'nextra-theme-docs'
import type { Metadata, Viewport } from 'next'
import { getPageMap } from 'nextra/page-map'

export const metadata: Metadata = {
  title: 'Swift AI SDK',
  description: 'Документация Swift AI SDK (порт Vercel AI SDK)'
}

export const viewport: Viewport = { themeColor: '#000' }

export default async function RootLayout({ children }: { children: ReactNode }) {
  const pageMap = await getPageMap()
  return (
    <html lang="ru" suppressHydrationWarning>
      <body>
        <Layout pageMap={pageMap}>{children}</Layout>
      </body>
    </html>
  )
}

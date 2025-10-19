import nextra from 'nextra'

// Nextra v4: theme is configured in app/layout via components; no theme/themeConfig here
const withNextra = nextra({
  // Add Nextra-specific options if needed
})

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
}

export default withNextra(nextConfig)

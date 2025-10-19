import React from 'react'

const config = {
  logo: <span>Swift AI SDK Docs</span>,
  project: {
    link: 'https://github.com/teunlao/swift-ai-sdk'
  },
  docsRepositoryBase: 'https://github.com/teunlao/swift-ai-sdk/tree/main/apps/docs-site',
  useNextSeoProps() {
    return { titleTemplate: '%s – Swift AI SDK' }
  },
  footer: {
    text: 'Swift AI SDK – Documentation'
  }
}

export default config

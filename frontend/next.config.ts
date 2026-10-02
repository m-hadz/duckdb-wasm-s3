const s3Endpoint = process.env.S3_INTERNAL_ENDPOINT ?? 'http://localhost:9000';
const s3Bucket = process.env.S3_BUCKET ?? 'data';

const nextConfig = {
  output: 'standalone',
  async rewrites() {
    return [
      {
        source: '/s3/:path*',
        destination: `${s3Endpoint}/${s3Bucket}/:path*`,
      },
    ];
  },
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          {
            key: 'Cross-Origin-Embedder-Policy',
            value: 'require-corp',
          },
          {
            key: 'Cross-Origin-Opener-Policy',
            value: 'same-origin',
          },
        ],
      },
    ];
  },
};

export default nextConfig;

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone", // keeps the Docker image slim (see Dockerfile)
  reactStrictMode: true,
};

export default nextConfig;

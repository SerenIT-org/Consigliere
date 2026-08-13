export function KvmWidget({ url }: { url: string }) {
  return (
    <a className="widget widget-kvm" href={url} target="_blank" rel="noreferrer">
      🖥️ KVM
    </a>
  );
}

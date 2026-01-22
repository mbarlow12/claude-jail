"""Bubblewrap command builder.

Provides primitives for constructing bwrap argument lists.
"""

import os
from pathlib import Path


class BwrapBuilder:
    """
    Builder for constructing bubblewrap command arguments.

    see usage of get_sandbox_home.

    """

    def __init__(self) -> None:
        """Initialize the builder with empty argument lists."""
        self.ns_args: list[str] = []
        self.pre_args: list[str] = []
        self.bind_args: list[str] = []
        self.env_args: list[str] = []
        self.seen: set[str] = set()

    def reset(self) -> None:
        """Reset all argument lists."""
        self.ns_args.clear()
        self.pre_args.clear()
        self.bind_args.clear()
        self.env_args.clear()
        self.seen.clear()

    def _ensure_parent(self, target: str) -> None:
        """Ensure parent directories exist in the sandbox."""
        if not target:
            return

        parts = Path(target).parts
        build = ""
        for part in parts[1:]:  # Skip root
            build = f"{build}/{part}"
            key = f"dir:{build}"
            if key in self.seen:
                continue
            self.pre_args.extend(["--dir", build])
            self.seen.add(key)

    def ro_bind(self, src: str | Path, dst: str | Path | None = None) -> bool:
        """Add a read-only bind mount."""
        src_path = Path(src)
        if not src_path.exists():
            return False

        dst_path = Path(dst) if dst else src_path
        dst_str = str(dst_path)

        bind_key = f"bind:{dst_str}"
        if bind_key in self.seen:
            return True

        # Resolve symlinks
        real_src = src_path.resolve()
        self._ensure_parent(str(dst_path.parent))
        self.bind_args.extend(["--ro-bind", str(real_src), dst_str])
        self.seen.add(bind_key)
        return True

    def bind(self, src: str | Path, dst: str | Path | None = None) -> bool:
        """Add a read-write bind mount."""
        src_path = Path(src)
        if not src_path.exists():
            return False

        dst_path = Path(dst) if dst else src_path
        dst_str = str(dst_path)

        bind_key = f"bind:{dst_str}"
        if bind_key in self.seen:
            return True

        # Resolve symlinks
        real_src = src_path.resolve()
        self._ensure_parent(str(dst_path.parent))
        self.bind_args.extend(["--bind", str(real_src), dst_str])
        self.seen.add(bind_key)
        return True

    def tmpfs(self, path: str) -> None:
        """Add a tmpfs mount."""
        self._ensure_parent(path)
        self.bind_args.extend(["--tmpfs", path])

    def symlink(self, target: str, link: str) -> None:
        """Add a symlink."""
        self.seen.add(f"dir:{link}")
        self.bind_args.extend(["--symlink", target, link])

    def dev(self, path: str = "/dev") -> None:
        """Mount /dev."""
        self.bind_args.extend(["--dev", path])

    def proc(self, path: str = "/proc") -> None:
        """Mount /proc."""
        self.bind_args.extend(["--proc", path])

    def setenv(self, name: str, value: str) -> None:
        """Set an environment variable."""
        self.env_args.extend(["--setenv", name, value])

    def chdir(self, path: str) -> None:
        """Set the working directory."""
        self.bind_args.extend(["--chdir", path])

    def unshare(self, *namespaces: str) -> None:
        """Unshare namespaces (user, pid, net, ipc, uts, cgroup)."""
        for ns in namespaces:
            match ns:
                case "user":
                    self.ns_args.append("--unshare-user")
                case "pid":
                    self.ns_args.append("--unshare-pid")
                case "net":
                    self.ns_args.append("--unshare-net")
                case "ipc":
                    self.ns_args.append("--unshare-ipc")
                case "uts":
                    self.ns_args.append("--unshare-uts")
                case "cgroup":
                    self.ns_args.append("--unshare-cgroup")

    def share(self, *namespaces: str) -> None:
        """Share namespaces (net)."""
        for ns in namespaces:
            if ns == "net":
                self.ns_args.append("--share-net")

    def system_base(self) -> None:
        """Mount base system directories."""
        self.ro_bind("/usr")

        # Handle /bin
        bin_path = Path("/bin")
        if bin_path.is_symlink():
            self.symlink("usr/bin", "/bin")
        elif bin_path.is_dir():
            self.ro_bind("/bin")

        # Handle /lib
        lib_path = Path("/lib")
        if lib_path.is_symlink():
            self.symlink("usr/lib", "/lib")
        elif lib_path.is_dir():
            self.ro_bind("/lib")

        # Handle /lib64
        lib64_path = Path("/lib64")
        if lib64_path.is_symlink():
            self.symlink("usr/lib64", "/lib64")
        elif lib64_path.is_dir():
            self.ro_bind("/lib64")

        # Handle /sbin
        sbin_path = Path("/sbin")
        if sbin_path.is_symlink():
            self.symlink("usr/sbin", "/sbin")
        elif sbin_path.is_dir():
            self.ro_bind("/sbin")

    def system_dns(self) -> None:
        """Mount DNS-related files."""
        dns_files = [
            "/etc/resolv.conf",
            "/etc/hosts",
            "/etc/nsswitch.conf",
            "/etc/host.conf",
            "/etc/gai.conf",
        ]
        for f in dns_files:
            if Path(f).is_file():
                self.ro_bind(f)

    def system_ssl(self) -> None:
        """Mount SSL certificate directories."""
        ssl_paths = [
            "/etc/ssl",
            "/etc/ca-certificates",
            "/etc/pki",
            "/etc/ca-certificates.conf",
        ]
        for p in ssl_paths:
            path = Path(p)
            if path.is_dir():
                self.ro_bind(p)
            elif path.is_file():
                self.ro_bind(p)

    def system_users(self) -> None:
        """Mount user/group files."""
        user_files = ["/etc/passwd", "/etc/group", "/etc/localtime"]
        for f in user_files:
            if Path(f).is_file():
                self.ro_bind(f)

    def bind_path_dirs(self) -> None:
        """Bind all directories in PATH."""
        path_env = os.environ.get("PATH", "")
        for directory in path_env.split(":"):
            if directory and Path(directory).is_dir():
                self.ro_bind(directory)

    def build(self) -> list[str]:
        """Build the final bwrap command."""
        cmd = ["bwrap", "--die-with-parent", "--new-session"]
        cmd.extend(self.ns_args)
        cmd.extend(self.pre_args)
        cmd.extend(self.bind_args)
        cmd.extend(self.env_args)
        return cmd

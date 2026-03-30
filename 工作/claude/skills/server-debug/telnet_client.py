#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Server Debug Console telnet 客户端

通过 TCP socket 连接服务器 Debug Console，发送 Lua 命令并接收输出。
已处理的已知问题：
  - 使用 CRLF (\r\n) 行结尾（console 要求）
  - 清洗 telnet 协商字节和 ANSI 控制字符
  - 等待 <end> 标记确认命令执行完成
  - 不受 MSYS/Git Bash 路径改写影响（纯 Python socket）

用法：
  python telnet_client.py <lua_command> [--port PORT] [--timeout SECONDS]

示例：
  python telnet_client.py "print('hello')"
  python telnet_client.py "dofile(\"/Test/test_xxx.lua\")"
  python telnet_client.py "dofile(\"/Test/test_xxx.lua\")" --port 8883 --timeout 30
  python telnet_client.py "getplayers()"
"""

import socket
import time
import sys
import re
import argparse


def clean_output(data):
    """清洗 telnet 协商字节和 ANSI 转义序列"""
    # 移除 telnet 协商字节 (IAC + WILL/WONT/DO/DONT + option)
    data = re.sub(b"\xff[\xfb-\xfe].", b"", data)
    # 解码
    text = data.decode("utf-8", errors="ignore")
    # 移除 ANSI 转义序列
    text = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", text)
    return text


def send_command(host, port, command, timeout=15):
    """发送命令到 Debug Console 并返回输出"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)

    try:
        sock.connect((host, port))
        time.sleep(0.5)

        # 读取欢迎消息
        welcome_data = sock.recv(4096)
        welcome = clean_output(welcome_data)
        print(welcome, end="")

        # 发送命令（必须用 CRLF 结尾）
        sock.sendall((command + "\r\n").encode("utf-8"))

        # 读取响应，直到收到 <end> 标记或超时
        response = b""
        start_time = time.time()
        sock.settimeout(3)

        while time.time() - start_time < timeout:
            try:
                chunk = sock.recv(16384)
                if not chunk:
                    break
                response += chunk
                # 检测 <end> 标记
                if b"<end>" in response:
                    time.sleep(0.3)
                    try:
                        extra = sock.recv(4096)
                        if extra:
                            response += extra
                    except socket.timeout:
                        pass
                    break
            except socket.timeout:
                if response:
                    break
                continue

        result = clean_output(response)
        print(result)

    except ConnectionRefusedError:
        print(
            "Error: 连接被拒绝 - 服务器未启动或端口 %d 不可用" % port,
            file=sys.stderr,
        )
    except socket.timeout:
        print(
            "Error: 连接超时 - 请确认服务器正在运行且端口 %d 正确" % port,
            file=sys.stderr,
        )
    except Exception as e:
        print("Error: %s" % e, file=sys.stderr)
        import traceback
        traceback.print_exc()
    finally:
        sock.close()


def main():
    parser = argparse.ArgumentParser(
        description="Server Debug Console telnet 客户端",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""示例:
  %(prog)s "print('hello')"
  %(prog)s "dofile(\\"/Test/test_xxx.lua\\")"
  %(prog)s "dofile(\\"/Test/test_xxx.lua\\")" --port 8883
  %(prog)s "getplayers()" --timeout 5
""",
    )
    parser.add_argument("command", help="要执行的 Lua 命令")
    parser.add_argument(
        "--host", default="127.0.0.1", help="服务器地址 (默认: 127.0.0.1)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8882,
        help="Debug Console 端口 (默认: 8882, logic_0)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=15,
        help="超时秒数 (默认: 15, 长脚本建议设 30-60)",
    )

    args = parser.parse_args()
    send_command(args.host, args.port, args.command, args.timeout)


if __name__ == "__main__":
    main()

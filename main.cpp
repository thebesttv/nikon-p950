/**
 * 使用 cosmo 编译，在运行时根据当前 OS 选择合适的 ffmpeg 和 ffprobe 路径
 * 使用方法：
 *   PATH=~/cosmo/cosmocc-4.0.2/bin/:$PATH make
 *   ./main.exe args...
 * 会执行命令：
 *   python.exe nikon-p950-vc --ffmpeg [...] --ffprobe [...] args...
 * - 其中 ffmpeg 和 ffprobe 的路径根据当前 OS 选择
 *   - Linux:   ffmpeg/linux/{ffmpeg,ffprobe}
 *   - Windows: ffmpeg/windows/{ffmpeg.exe,ffprobe.exe}
 * - python.exe 是 Cosmos 打包的版本
 * - args... 是给定参数，传递给 nikon-p950-vc 脚本
 */

#include <chrono>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <stdio.h>
#include <string>
#include <vector>

#include <libc/cosmo.h>
#include <libc/dce.h>

#include <spdlog/fmt/fmt.h>
#include <spdlog/fmt/ranges.h>
#include <spdlog/spdlog.h>

namespace fs = std::filesystem;

const char *SCRIPT_NAME = "nikon-p950-vc";

/*****************************************************************
 * fmt::formatter for std::filesystem::path
 *****************************************************************/

template <>
struct fmt::formatter<std::filesystem::path> : fmt::formatter<std::string> {
  auto format(const std::filesystem::path &p, format_context &ctx) const
      -> decltype(ctx.out()) {
    return formatter<std::string>::format(p.string(), ctx);
  }
};
/*****************************************************************
 * Helper functions
 *****************************************************************/

void requireTrue(bool condition, const std::string &message) {
  if (!condition) {
    spdlog::error("Assertion failed: {}", message);
    throw std::runtime_error(message);
  }
}

void requireExists(const std::string &path) {
  requireTrue(access(path.c_str(), F_OK) == 0,
              "File " + path + " does not exist");
}

int runProgram(const std::vector<std::string> &args) {
  // 创建 C 字符串数组来存储参数
  std::vector<char *> c_args;
  for (const auto &arg : args) {
    c_args.push_back(const_cast<char *>(arg.c_str()));
  }
  c_args.push_back(nullptr); // 添加 NULL 作为结束标志

  // 创建新的进程
  pid_t pid = fork();

  if (pid == -1) {
    // 错误处理，创建进程失败
    perror("fork");
    return -1;
  } else if (pid == 0) {
    // 在子进程中执行程序
    if (execvp(c_args[0], c_args.data()) == -1) {
      // 如果execvp返回-1，说明执行失败
      perror("execvp");
      return -1;
    }
    // 不可能到达这里，是为了避免编译器警告
    exit(127);
  } else {
    // 在父进程中等待子进程结束
    int status;
    waitpid(pid, &status, 0);

    if (WIFEXITED(status)) {
      // 子进程正常退出，返回退出状态
      return WEXITSTATUS(status);
    } else {
      // 子进程异常退出
      return -1;
    }
  }
}

int main(int argc, char *argv[]) {
  fs::path binPath = std::filesystem::canonical(argv[0]);
  spdlog::info("Executable path: {}", binPath);

  fs::path rootDir = binPath.parent_path();
  spdlog::info("Root directory: {}", rootDir);

  fs::path pythonPath = rootDir / "python.exe";
  spdlog::info("Python path: {}", pythonPath);
  requireExists(pythonPath);

  fs::path scriptPath = rootDir / SCRIPT_NAME;
  spdlog::info("Script path: {}", scriptPath);
  requireExists(scriptPath);

  fs::path ffmpegPath, ffprobePath;
  if (IsLinux()) {
    ffmpegPath = rootDir / "ffmpeg/linux/ffmpeg";
    ffprobePath = rootDir / "ffmpeg/linux/ffprobe";
    spdlog::info("Current OS: Linux");
  } else if (IsWindows()) {
    ffmpegPath = rootDir / "ffmpeg/windows/ffmpeg.exe";
    ffprobePath = rootDir / "ffmpeg/windows/ffprobe.exe";
    spdlog::info("Current OS: Windows");
  } else {
    requireTrue(false, "Unsupported OS");
    return 1;
  }

  spdlog::info("FFmpeg path:  {}", ffmpegPath);
  spdlog::info("FFprobe path: {}", ffprobePath);
  requireExists(ffmpegPath);
  requireExists(ffprobePath);

  std::vector<std::string> command{pythonPath.string(), scriptPath.string(),
                                   "--ffmpeg",          ffmpegPath.string(),
                                   "--ffprobe",         ffprobePath.string()};
  for (int i = 1; i < argc; ++i) {
    command.push_back(argv[i]);
  }

  spdlog::info("Executing script {} ...", SCRIPT_NAME);
  auto start = std::chrono::high_resolution_clock::now();
  int ret = runProgram(command);
  auto end = std::chrono::high_resolution_clock::now();
  auto duration =
      std::chrono::duration_cast<std::chrono::milliseconds>(end - start);
  spdlog::info("Script execution time: {:.3f} seconds",
               duration.count() / 1000.0);
  if (ret != 0) {
    spdlog::error("Script execution failed with return code: {}", ret);
    return ret;
  }
}

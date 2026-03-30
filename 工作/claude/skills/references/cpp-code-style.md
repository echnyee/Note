<!-- 源地址：https://docs.corp.kuaishou.com/k/home/VXZORuZbxFF8/fcAD2yYZVmtqYqcxeJXCkyXYB?ro=false -->
# 服务器引擎C++插件编码规范

## 基础风格
1. 插件目录下有 `.clang-format`，**提交前都格式化一下**，保证代码格式统一。
2. C++基础风格规范（冲突时以本文档为准）：参考 **Google 开源项目风格指南**。

在上文档的基础上，进行以下补充：
* **单行单定义**：一行代码只允许进行一个变量定义。
* **变量均需初始化**：任何不能通过构造函数做初始化的变量定义，必须赋予初始值；特别需要注意结构体（详情见“成员初始化”小节）。
  ```cpp
  struct SomeStruct {
    int field;
  };

  void SomeFunction() {
      // 错误示范：s的field是未初始化的，可能是任意值
      SomeStruct s; 
      // ... 使用s的业务逻辑代码
  }
  ```
* **函数返回值约定**：保持一致的出错风格。
  * 如果函数一定会成功，返回 `void`。
  * 如果函数会失败，返回 `bool` 值；如果关心失败的原因，有两种处理方式：返回一个明确的错误枚举，或者传递一个错误码指针来存放错误的原因。默认**不允许返回int值作为错误码**。
* **大括号保护**：单行 `if` 语句也使用大括号，防止编辑出错。
  ```cpp
  if (condition) { // 防止编辑出错造成代码逻辑错误，使用大括号保护
    DoSomething();
  }
  ```
* `case` 语句如果没有变量定义不需要特地加 `{}`。

## 宏和模板
* 代码中尽可能**不要出现宏的使用**，如果可以用 `constexpr`、`inline` 等代替，请使用代替。
* 若必须使用宏，请注意使用 `do{...}while(false)` 来保护代码段，使用 `()` 来保护变量参数。
* **不要使用复杂的模板编程**。

## 枚举
使用 C++ 的强枚举类型（`enum class`）。

## 成员初始化
结构体和类非静态成员变量原则上在声明时就地初始化，需要注意的是**初始化列表的效果总是优于就地初始化的**。

### 就地初始化
```cpp
struct SimpleType {
    int field = 0; // since C++11, works now!
    char sz[10] = {}; // 等价于memset(sz, 0, sizeof(sz))
    std::string name = "Hello World";
};
```

### 初始化顺序
```cpp
class TestA {
public:
    TestA(int m1, const std::string &m3) :
        m1_(m1), // 第一步: m1_=0
        m3_(m3)  // 第二步: m3_=""
    {}
  
private:
    int m1_ = 1; // 跳过
    int m2_ = 2; // 第三步: m2_=2
    std::string m3_ = "123"; // 跳过
    std::string m4_ = "abc"; // 第四步m4_="abc"
};
```
注意，如果不是初始化列表，会执行就地初始化然后再次赋值：
```cpp
class TestA {
public:
    TestA(int m1, const std::string &m3) {
        m1_ = m1; // 第五步
        m3_ = m3; // 第六步
    }
private:
    int m1_ = 1; // 第一步
    int m2_ = 2; // 第二步
    std::string m3_ = "123"; // 第三步
    std::string m4_ = "abc"; // 第四步
};
```

### 数组初始化
```cpp
int arr[5];         // 未初始化
int arr[5] = {};    // {0,0,0,0,0}
int arr[5] = {0};   // 等价arr[5] = {}
int arr[5] = {1, 1};// {1,1,0,0,0} 未被初始化的元素将全部被置为0
char a[5] = "";     // "     "
char a[5] = "a";    // "a    "
```
数组初始化只有全部初始化一种方式，对于性能热点需要根据实际情况来决定是否初始化，而不是随手写一个 `={}`。对于字符串缓存：
```cpp
char str[1024];
str[0] = '\0'; // 比如作为字符串缓存，可以显式赋值第一个值
```

## #Include 规范
* `#include` 必须在文件的开头进行，如果有例外，需进行特殊说明。
* 按照以下顺序导入头文件：
  1. 配套的头文件
  2. C语言系统库头文件
  3. C++标准库头文件
  4. 其他库的头文件
  5. base目录的头文件
  6. 本项目的头文件
* 为了使工程依赖清晰，尽可能**不要在头文件中#include其他头文件**。
* 不允许头文件循环依赖。
* 代码文件和头文件都直接 `#include` 其依赖的头文件，不要依赖间接导入。

## inline
C++17 之后 `inline` 不再是内联优化的意思：
* 类定义中实现的函数默认就是 `inline` 的，不要再显式声明成 `inline`。
* 模板默认就是 `inline` 的，不要再显式声明成 `inline`。
* 头文件中定义的函数需要显式声明成 `inline`，否则会报重定义错误。
* 可以使用 `inline` 变量功能，static 变量直接在头文件定义：
  ```cpp
  class MyClass { 
  public: 
      inline static int s_var = 10; 
  }; 
  ```

## Lambda和std::function
* Lambda 始终存在栈上，离开了作用域就会被自动回收。注意不能捕获太多值，避免栈溢出。
* **Lambda表达式不允许使用 `[=]`, `[&]` 来全捕获**，必须明确捕获列表。

## Lua堆栈操作
* **不要改变入参参数**，通过 `lua_pushvalue()` 来压栈，再进行操作。
* 进行 Lua 操作的函数有义务**保证堆栈平衡**，无论何种情况，堆栈变化一定是确定的。如果不是确定的，应返回 int 类型，代表堆栈变化的个数，统一使用 `-1` 表示错误，并保持堆栈平衡。
* 有了这些前提，我们才好做堆栈平衡检查。

## 静态和全局变量
* **禁止使用类的静态存储周期变量**。由于构造和析构函数调用顺序的不确定性，它们会导致难以发现的bug。不过 `constexpr` 变量除外。
* 静态生存周期的对象（全局变量，静态变量，静态类成员变量和函数静态变量），必须是**原生数据类型（POD: Plain Old Data）**：即 int, char 和 float，以及 POD 类型的指针、数组和结构体。
* **全局变量推荐继承自 `Global` 类实现**，能保证构造和析构顺序，所有业务C++构造和析构顺序应明确：
  ```cpp
  GlobalObjectManager::set(new GlobalObjectManager());
  GlobalObjectManager::inst().initGlobal<MoveDataManager>();
  GlobalObjectManager::inst().initGlobal<CombatDataManager>();
  GlobalObjectManager::inst().initGlobal<ActorRpcHandler>();
  ```

## 内存管理
* 非临时对象必须有明确且唯一的归属。
* 对象的生命周期必须明确和显式的管理。
* 存在对象动态分配的函数必须保证**单一出口**，避免遗忘释放对象。
* 临时对象生命周期超出分配者作用域使用**引用计数**管理或 `std::shared_ptr` 管理。
* 尽量在启动时预分配内存。

## C++特性
* 使用 `nullptr` 替代 `NULL`。
* 覆盖父类方法的签名必须加上 `override`。
* 优先使用 `auto`，尤其是在类型转换或使用到复杂类型时（如迭代器）。
* 优先使用 `using` 而不是 `typedef`。
* 优先使用 `std::make_shared` / `std::make_unique`，而不是先 new 再调用智能指针。
* 如果后续代码不需要使用某个复杂变量，优先使用**移动语义**（如构建了一个复杂的结构，然后 push_back 的情况）。
* 在能使用 `constexpr` 的情况，尽量使用。

## 命名规范
* **C++文件名**：全小写+下划线分隔，头文件使用 `.hpp` 后缀，源文件使用 `.cpp` 后缀。（如 `lua_script.hpp`）
* **类/结构体名**：CamelCase，例如 `EngineProxy`。
* **成员函数**：CamelCase，例如 `UseSkill`。
* **类成员变量**：全小写下划线分隔，且**以下划线结尾**，例如 `nav_tick_frame_`。
* **结构体成员变量**：全小写下划线分隔，**不以下划线结尾**，例如 `nav_tick_frame`。
* **静态变量**：`s_` 开头，例如 `s_send_buffer_`。
* **全局变量**：`g_` 开头，例如 `g_log_impl`。
* **常量**：`k` 开头（例如 `kActorsBufferSize`），或者全大写下划线分隔（例如 `DEFAULT_BUFFER_SIZE`）。
* **宏**：全大写下划线分隔，例如 `KG_LOG_FAILED_JUMP`。

## 目录说明（crates目录下）
* `vendor`：第三方库
* `src`：我们自己写的代码
  * `base`：基础代码，log、lua基础库、math等，跟具体业务无关。理论上很少需要去修改此目录，不要随意添加。
  * `data`：存放数据定义和结构体代码。
  * `biz`：项目的业务逻辑都放在此目录，比如技能、子弹等。
  * `recast`：recast库代码。

**定义文件依赖关系**：
* `biz/data/data_define.hpp`：定义了数据模块所需的基础类型。
* `biz/data/combat/combat_define.hpp`：定义了战斗模块特有的定义。
* `biz/scene/scene_define.hpp`：scene模块包含该头文件即可获得大部分定义。
* `biz/scene/combat/common.hpp`：combat模块包含该头文件即可获得大部分定义。

## Hotfix (热更规范)
引擎插件支持C++ Hotfix，但为了使代码能够热更，需要遵循以下规范：
* **不要使用 local static 函数和 local static 变量**。
  * 允许使用类的静态成员函数和静态成员变量。
  ```cpp
  // 错误示范：无法热更
  static void func() {}
  static int a = 10;
  void global_func() {
      static int b = 10; // 函数内定义的static变量，热更会出问题
  }
  ```
* 对于模板，需要在头文件中进行**显式的实例化声明**，并注意包裹 `HOTFIX` 编译宏，否则无法热更。
  ```cpp
  #ifndef HOTFIX
  template void HotfixTest::class_templace_func<int>();
  template void template_func<int>();
  template class HotfixTestTemplate<int>;
  #endif
  ```

## 性能注意
1. 注意查找性能，`std::map` 和 `std::unordered_map` 也可能成为性能热点，需要仔细设计数据结构。
2. 注意遍历性能，高频遍历需要考虑良好的内存布局。
3. 慎用 `std::string`，大量使用往往意味着低效，如无法避免，优先考虑 `std::string_view`。
4. 尽可能避免 Lua 字符串转成 `std::string`，考虑是否可以使用字符指针来进行操作。
5. 避免没有意义的对象拷贝。
6. 避免无脑使用 `shared_ptr`。

## 崩溃注意
1. **空指针判定**：一定要判定，若确定不允许传入空指针则改传引用。
2. **迭代器遍历**：如果调用外部接口，一定要先拷贝再遍历以免失效（或采用其他安全写法）。
3. **数组越界**：警惕越界判定，尤其是枚举转 int 作为下标访问时，枚举可能是未定义值。
4. **除零**：除法一定要确保除数不为零。

## 问题案例
1. **传参类型**：基础类型（如 int, float）**不要传 const &**，直接传值类型即可（值类型拷贝4-8字节且编译器能做更好的优化）；非基础类型（复杂对象），传 `const &`。
2. **类型别名**：谨慎定义通用的类型别名。推荐使用命名空间限制，且名字独特，避免像之前代码中 `guid_t` 存在两个完全不同的定义导致冲突。
3. **不要过度包装**：不必追求使用C++高级特性（如 `std::transform`），简单的 `for` 循环往往更清晰高效。如果数组大小能预先确定，使用 `reserve` 预分配内存。
4. **注重基础质量**：避免基础算法的低级逻辑冗余（例如方向归一化没必要写低效复杂的 `while` 循环）。
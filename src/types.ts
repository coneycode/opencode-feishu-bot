/**
 * opencode-chat-channel — 多渠道抽象层
 *
 * 每个渠道（飞书、企业微信等）实现 ChatChannel 接口即可接入。
 */

import type { Plugin } from "@opencode-ai/plugin";

/** opencode Plugin 客户端类型（从 Plugin 回调参数中提取） */
export type PluginClient = Parameters<Plugin>[0]["client"];

// ─── 渠道消息标准化模型 ─────────────────────────────────────────────────────

/** 从渠道收到的标准化消息 */
export interface IncomingMessage {
  /** 消息唯一 ID（用于去重） */
  messageId: string;
  /** 用户唯一标识（用于 session 绑定，不同渠道格式不同） */
  userId: string;
  /** 回复目标 ID（群 ID / 用户 ID，由渠道决定具体含义） */
  replyTarget: string;
  /** 消息文本内容 */
  text: string;
}

// ─── Channel 接口 ──────────────────────────────────────────────────────────

/**
 * ChatChannel — 渠道适配器接口
 *
 * 每个渠道实现此接口：
 *   - name: 渠道标识符（用于日志、配置 key）
 *   - start(): 启动监听，收到消息时调用 onMessage 回调
 *   - send(): 向指定 target 发送文本回复
 *   - sendThinkingCard(): 发送占位卡片，返回可更新的 ID（可选）
 *   - updateThinkingCard(): 更新占位卡片内容（可选，旧接口向下兼容）
 *   - patchProgress(): 更新卡片为进度状态，外部摘要+内部详情折叠面板（可选）
 *   - patchDone(): 更新卡片为完成状态（可选）
 *   - stop(): 优雅关闭（可选）
 */
export interface ChatChannel {
  /** 渠道唯一名称，如 "feishu"、"wecom" */
  readonly name: string;

  /**
   * 启动渠道监听。
   * 每当收到用户消息时，调用 onMessage(msg)。
   */
  start(onMessage: (msg: IncomingMessage) => Promise<void>): Promise<void>;

  /**
   * 向指定目标发送文本消息。
   * replyTarget 为 IncomingMessage.replyTarget。
   */
  send(replyTarget: string, text: string): Promise<void>;

  /**
   * 发送"正在思考"占位卡片，返回可用于后续更新的占位消息 ID。
   * 返回 null 表示该渠道不支持更新式占位（降级为无占位）。
   * 可选——未实现的渠道会跳过思考展示。
   */
  sendThinkingCard?(replyTarget: string): Promise<string | null>;

  /**
   * 更新占位消息的内容（旧接口，向下兼容）。
   * @param placeholderId  sendThinkingCard 返回的 ID
   * @param statusText     新状态文本
   */
  updateThinkingCard?(placeholderId: string, statusText: string): Promise<void>;

  /**
   * 更新思考卡片为进度状态（节流调用）。
   * 卡片外部显示 summary 摘要，折叠面板内部展示 detail 详细内容。
   * @param placeholderId  sendThinkingCard 返回的 ID
   * @param summary        外部摘要文字（如"🤔 正在推理..."）
   * @param detail         折叠面板内部展开后的详细内容（reasoning / text 累积）
   * @param stage          当前阶段，用于选择卡片图标和样式
   */
  patchProgress?(
    placeholderId: string,
    summary: string,
    detail: string,
    stage: "reasoning" | "replying"
  ): Promise<void>;

  /**
   * 更新思考卡片为完成状态。
   * @param placeholderId  sendThinkingCard 返回的 ID
   * @param detail         展开后显示的完整内容（reasoning + text 摘要）
   */
  patchDone?(placeholderId: string, detail: string): Promise<void>;

  /** 优雅停止渠道（可选）。 */
  stop?(): Promise<void>;
}

// ─── 渠道工厂函数类型 ──────────────────────────────────────────────────────

/**
 * ChannelFactory — 渠道工厂函数签名
 *
 * 工厂函数负责读取配置、验证凭证、构造并返回 ChatChannel 实例。
 * 若凭证未配置，应返回 null（插件将跳过该渠道并记录日志）。
 */
export type ChannelFactory = (
  client: PluginClient
) => Promise<ChatChannel | null>;

// ─── 已知渠道名称 ──────────────────────────────────────────────────────────────────

/**
 * 已注册的渠道名称。
 * 新增渠道时在此处添加对应字面量，便于编译期检查。
 */
export type ChannelName = "feishu" | "wecom";

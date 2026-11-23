import { useState } from 'react';

import {
  Alert,
  Button,
  Card,
  Descriptions,
  Form,
  Input,
  Modal,
  Popconfirm,
  Space,
  Steps,
  Table,
  Tag,
  Typography,
  Upload,
} from 'antd';
import type { UploadFile } from 'antd';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useParams } from 'react-router-dom';

import * as api from '../api/client.js';

interface PackVersion {
  id: string;
  version: number;
  format: string;
  minAppBuild: number;
  status: 'draft' | 'validated' | 'published' | 'revoked';
  source: { name: string; revision: string } | null;
  notes: { ar: string } | null;
  channels: string[];
}

/** SHA-256 of a file in the browser before upload (02 §6). */
async function sha256(file: File): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

const statusColor: Record<PackVersion['status'], string> = {
  draft: 'default',
  validated: 'blue',
  published: 'green',
  revoked: 'red',
};

/**
 * `/packs/:id` and the new-version flow (02 §6): a four-step Steps of data,
 * upload (sha256 computed in the browser), validate and release.
 */
export function PackPage({ role }: { role: 'owner' | 'editor' }) {
  const { packId = '' } = useParams();
  const queryClient = useQueryClient();
  const [step, setStep] = useState(0);
  const [versionId, setVersionId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [files, setFiles] = useState<UploadFile[]>([]);
  const [releasing, setReleasing] = useState<string | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['versions', packId],
    queryFn: () => api.getJson<{ versions: PackVersion[] }>(`/packs/${packId}/versions`),
  });

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['versions', packId] });
    await queryClient.invalidateQueries({ queryKey: ['packs'] });
  };

  const createVersion = useMutation({
    mutationFn: (values: { format: string; sourceName?: string; sourceRevision?: string; notesAr?: string }) =>
      api.sendJson<{ id: string; version: number }>('POST', `/packs/${packId}/versions`, values),
    onSuccess: async (created) => {
      setVersionId(created.id);
      setError(null);
      setStep(1);
      await refresh();
    },
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل إنشاء الإصدار.'),
  });

  const uploadFiles = useMutation({
    mutationFn: async () => {
      if (!versionId) throw new Error('No draft version.');
      const declared = await Promise.all(
        files.map(async (file) => ({
          path: file.name,
          sha256: await sha256(file.originFileObj as File),
          size: (file.originFileObj as File).size,
          body: file.originFileObj as File,
        })),
      );

      const { uploads } = await api.sendJson<{ uploads: { path: string; url: string }[] }>(
        'POST',
        `/pack-versions/${versionId}/files`,
        { files: declared.map(({ path, sha256: digest, size }) => ({ path, sha256: digest, size })) },
      );

      for (const upload of uploads) {
        const file = declared.find((candidate) => candidate.path === upload.path);
        if (!file) throw new Error(`The server asked for an unknown file ${upload.path}.`);
        const response = await fetch(upload.url, { method: 'PUT', body: file.body });
        if (!response.ok) throw new Error(`Upload of ${file.path} failed (${response.status}).`);
      }
    },
    onSuccess: () => {
      setError(null);
      setStep(2);
    },
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل الرفع.'),
  });

  const validate = useMutation({
    mutationFn: () => api.sendJson<{ files: number }>('POST', `/pack-versions/${versionId}/validate`),
    onSuccess: async () => {
      setError(null);
      setStep(3);
      await refresh();
    },
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل التحقق.'),
  });

  const release = useMutation({
    mutationFn: ({ id, channel }: { id: string; channel: string }) =>
      api.sendJson('POST', `/pack-versions/${id}/release`, { channel }),
    onSuccess: async () => {
      setReleasing(null);
      setError(null);
      await refresh();
    },
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل النشر.'),
  });

  const revoke = useMutation({
    mutationFn: (id: string) => api.sendJson('POST', `/pack-versions/${id}/revoke`),
    onSuccess: refresh,
    onError: (cause) => setError(cause instanceof Error ? cause.message : 'فشل السحب.'),
  });

  return (
    <>
      <Typography.Title level={4}>
        الحزمة <span dir="ltr">{packId}</span>
      </Typography.Title>

      {error && <Alert type="error" message={error} closable onClose={() => setError(null)} style={{ marginBottom: 16 }} />}

      <Steps
        current={step}
        style={{ marginBottom: 24 }}
        items={[
          { title: 'البيانات' },
          { title: 'رفع الملفات' },
          { title: 'التحقق' },
          { title: 'النشر' },
        ]}
      />

      <Card title="إصدار جديد" style={{ marginBottom: 24 }}>
        {step === 0 && (
          <Form
            layout="vertical"
            initialValues={{ format: `${packId.replace(/-farsh$/, '')}@1` }}
            onFinish={(values) => createVersion.mutate(values as { format: string })}
          >
            <Form.Item name="format" label="الصيغة" rules={[{ required: true }]}>
              <Input dir="ltr" />
            </Form.Item>
            <Form.Item name="sourceName" label="اسم المصدر">
              <Input />
            </Form.Item>
            <Form.Item name="sourceRevision" label="رقم نسخة المصدر">
              <Input dir="ltr" />
            </Form.Item>
            <Form.Item name="notesAr" label="ملاحظات">
              <Input.TextArea rows={2} />
            </Form.Item>
            <Button type="primary" htmlType="submit" loading={createVersion.isPending}>
              إنشاء إصدار تجريبي
            </Button>
          </Form>
        )}

        {step === 1 && (
          <>
            <Typography.Paragraph type="secondary">
              تُحسب بصمة sha256 في المتصفح قبل الرفع، ويقارنها السيرفر بعد الاستلام.
            </Typography.Paragraph>
            <Upload
              multiple
              beforeUpload={() => false}
              fileList={files}
              onChange={({ fileList }) => setFiles(fileList)}
            >
              <Button>اختر الملفات</Button>
            </Upload>
            <Button
              type="primary"
              style={{ marginTop: 16 }}
              disabled={files.length === 0}
              loading={uploadFiles.isPending}
              onClick={() => uploadFiles.mutate()}
            >
              رفع
            </Button>
          </>
        )}

        {step === 2 && (
          <>
            <Typography.Paragraph>رُفعت الملفات. شغّل التحقق لمطابقة الحجم والبصمة والصيغة.</Typography.Paragraph>
            <Button type="primary" loading={validate.isPending} onClick={() => validate.mutate()}>
              بدء التحقق
            </Button>
          </>
        )}

        {step === 3 && (
          <>
            <Alert type="success" message="الإصدار صالح. اختر قناة للنشر." style={{ marginBottom: 16 }} />
            <Space>
              <Button onClick={() => release.mutate({ id: versionId!, channel: 'internal' })}>internal</Button>
              <Button onClick={() => release.mutate({ id: versionId!, channel: 'beta' })}>beta</Button>
              {role === 'owner' && (
                <Button type="primary" onClick={() => release.mutate({ id: versionId!, channel: 'stable' })}>
                  stable
                </Button>
              )}
            </Space>
            <div style={{ marginTop: 16 }}>
              <Button onClick={() => { setStep(0); setVersionId(null); setFiles([]); }}>إصدار آخر</Button>
            </div>
          </>
        )}
      </Card>

      <Table
        rowKey="id"
        loading={isLoading}
        dataSource={data?.versions ?? []}
        pagination={false}
        columns={[
          { title: 'الإصدار', dataIndex: 'version' },
          { title: 'الصيغة', dataIndex: 'format', render: (value: string) => <span dir="ltr">{value}</span> },
          {
            title: 'الحالة',
            dataIndex: 'status',
            render: (status: PackVersion['status']) => <Tag color={statusColor[status]}>{status}</Tag>,
          },
          {
            title: 'القنوات',
            dataIndex: 'channels',
            render: (channels: string[]) => (channels.length ? channels.map((c) => <Tag key={c}>{c}</Tag>) : '—'),
          },
          {
            title: 'المصدر',
            dataIndex: 'source',
            render: (source: PackVersion['source']) =>
              source ? `${source.name} · ${source.revision.slice(0, 8)}` : '—',
          },
          {
            title: 'إجراءات',
            key: 'actions',
            render: (_: unknown, row: PackVersion) => (
              <Space>
                {(row.status === 'validated' || row.status === 'published') && (
                  <Button size="small" onClick={() => setReleasing(row.id)}>
                    نشر
                  </Button>
                )}
                {row.status !== 'revoked' && role === 'owner' && (
                  <Popconfirm
                    title="سحب هذا الإصدار من كل القنوات؟"
                    okText="سحب"
                    cancelText="إلغاء"
                    onConfirm={() => revoke.mutate(row.id)}
                  >
                    <Button size="small" danger>
                      سحب
                    </Button>
                  </Popconfirm>
                )}
              </Space>
            ),
          },
        ]}
      />

      <Modal
        open={releasing !== null}
        title="النشر لقناة"
        onCancel={() => setReleasing(null)}
        footer={null}
      >
        <Descriptions column={1} size="small" style={{ marginBottom: 16 }}>
          <Descriptions.Item label="ملاحظة">
            beta يظهر للمختبرين فورًا، وstable لكل المستخدمين. النشر إلى stable يتطلب مالكًا.
          </Descriptions.Item>
        </Descriptions>
        <Space>
          <Button onClick={() => release.mutate({ id: releasing!, channel: 'internal' })}>internal</Button>
          <Button onClick={() => release.mutate({ id: releasing!, channel: 'beta' })}>beta</Button>
          {role === 'owner' && (
            <Button type="primary" onClick={() => release.mutate({ id: releasing!, channel: 'stable' })}>
              stable
            </Button>
          )}
        </Space>
      </Modal>
    </>
  );
}

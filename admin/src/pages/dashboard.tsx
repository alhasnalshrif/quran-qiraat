import { Alert, Card, Col, Row, Statistic, Table, Tag, Typography } from 'antd';
import { useQuery } from '@tanstack/react-query';

import * as api from '../api/client.js';

interface PackSummary {
  packId: string;
  titleAr: string;
  channels: Record<string, number>;
}

interface PacksResponse {
  packs: PackSummary[];
}

/** `/` (02 §6): the latest version per pack and channel, and a stale-stable warning. */
export function DashboardPage() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['packs'],
    queryFn: () => api.getJson<PacksResponse>('/packs'),
  });

  const packs = data?.packs ?? [];
  const outdated = packs.filter((pack) => {
    const stable = pack.channels.stable;
    const beta = pack.channels.beta;
    return stable !== undefined && beta !== undefined && beta > stable;
  });

  return (
    <>
      <Typography.Title level={4}>الرئيسية</Typography.Title>

      <Row gutter={16} style={{ marginBottom: 24 }}>
        <Col span={8}>
          <Card>
            <Statistic title="الحزم" value={packs.length} />
          </Card>
        </Col>
        <Col span={8}>
          <Card>
            <Statistic title="إصدارات مستقرة منشورة" value={packs.filter((p) => p.channels.stable).length} />
          </Card>
        </Col>
        <Col span={8}>
          <Card>
            <Statistic
              title="stable أقدم من beta"
              value={outdated.length}
              {...(outdated.length > 0 ? { valueStyle: { color: '#cf1322' } } : {})}
            />
          </Card>
        </Col>
      </Row>

      {error && <Alert type="error" message={String(error)} style={{ marginBottom: 16 }} />}
      {outdated.length > 0 && (
        <Alert
          type="warning"
          style={{ marginBottom: 16 }}
          message="توجد حزم فيها beta أحدث من stable"
          description={outdated.map((pack) => `${pack.titleAr}: beta ${pack.channels.beta} ← stable ${pack.channels.stable}`).join(' · ')}
        />
      )}

      <Table
        rowKey="packId"
        loading={isLoading}
        dataSource={packs}
        pagination={false}
        columns={[
          { title: 'الحزمة', dataIndex: 'titleAr' },
          { title: 'المعرّف', dataIndex: 'packId', render: (value: string) => <code dir="ltr">{value}</code> },
          {
            title: 'stable',
            dataIndex: ['channels', 'stable'],
            render: (value?: number) => (value ? <Tag color="green">{value}</Tag> : '—'),
          },
          {
            title: 'beta',
            dataIndex: ['channels', 'beta'],
            render: (value?: number) => (value ? <Tag color="blue">{value}</Tag> : '—'),
          },
          {
            title: 'internal',
            dataIndex: ['channels', 'internal'],
            render: (value?: number) => (value ? <Tag>{value}</Tag> : '—'),
          },
        ]}
      />
    </>
  );
}

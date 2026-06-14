import React from 'react';
import { Box, Chip } from '@material-ui/core';
import { Content, Header, Page } from '@backstage/core-components';
import { TemplatesTab } from './TemplatesTab';
import { JobHistoryTab } from './JobHistoryTab';

export function AapManagementPage() {
  const [tab, setTab] = React.useState(0);

  return (
    <Page themeId="tool">
      <Header
        title="AAP Automation Templates"
        subtitle="Browse, search, and launch Ansible Automation Platform job templates"
      />
      <Content>
        <Box mb={2} display="flex" gridGap={8}>
          <Chip
            clickable
            color={tab === 0 ? 'primary' : 'default'}
            label="Templates"
            onClick={() => setTab(0)}
          />
          <Chip
            clickable
            color={tab === 1 ? 'primary' : 'default'}
            label="Run history"
            onClick={() => setTab(1)}
          />
        </Box>
        <Box hidden={tab !== 0}>
          <TemplatesTab />
        </Box>
        <Box hidden={tab !== 1}>
          <JobHistoryTab />
        </Box>
      </Content>
    </Page>
  );
}

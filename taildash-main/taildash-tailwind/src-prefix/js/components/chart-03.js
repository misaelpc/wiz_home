import ApexCharts from 'apexcharts';

// ===== chartTwo
const chart03 = () => {
  const chartThreeOptions = {
    series: [72, 27],
    chart: {
      height: 250,
      type: 'radialBar',
    },

    responsive: [
      {
        breakpoint: 768,
        options: {
          chart: {
            height: 300,
          },
        },
      },
    ],

    plotOptions: {
      radialBar: {
        dataLabels: {
          name: {
            show: true,
            fontSize: '22px',
            offsetY: -2,
          },
          value: {
            fontSize: '16px',
            offsetY: 2,
          },
          total: {
            show: true,
            label: 'Total',
          },
        },
      },
    },
    dataLabels: {
      enabled: true,
    },
    colors: ['#3056D3', '#13C296'],
    labels: ['Sent', 'Receive'],
    legend: {
      show: true,
      position: 'bottom',
    },
  };

  const chartSelector = document.querySelectorAll('#chartThree');

  if (chartSelector.length) {
    const chartThree = new ApexCharts(
      document.querySelector('#chartThree'),
      chartThreeOptions
    );
    chartThree.render();
  }
};

export default chart03;

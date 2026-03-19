import ApexCharts from 'apexcharts';

// ===== chartTwo
const chart02 = () => {
    const chartTwoOptions = {
      series: [
        {
          name: 'Sales',
          data: [44, 55, 41, 67, 22, 43, 65],
        },
        {
          name: 'Revenue',
          data: [13, 23, 20, 8, 13, 27, 15],
        },
      ],
      colors: ['#3056D3', '#13C296'],
      chart: {
        type: 'bar',
        height: 240,
        stacked: true,
        toolbar: {
          show: false,
        },
        zoom: {
          enabled: false,
        },
      },

      responsive: [
        {
          breakpoint: 480,
          options: {
            legend: {
              position: "bottom",
              offsetX: -10,
              offsetY: 0,
            },
          },
        },
        {
          breakpoint: 1536,
          options: {
            plotOptions: {
              bar: {
                borderRadius: 3,
                columnWidth: "15%",
              },
            },
          },
        },
      ],
      plotOptions: {
        bar: {
          horizontal: false,
          borderRadius: 8,
          columnWidth: "15%",
          borderRadiusApplication: "end",
          borderRadiusWhenStacked: "last",
        },
      },
      dataLabels: {
        enabled: false,
      },

      xaxis: {
        type: 'datetime',
        categories: [
          '01/01/2011 GMT',
          '01/02/2011 GMT',
          '01/03/2011 GMT',
          '01/04/2011 GMT',
          '01/05/2011 GMT',
          '01/06/2011 GMT',
          '01/07/2011 GMT',
        ],
      },
      legend: {
        position: 'top',
        horizontalAlign: 'left',
        fontFamily: 'inter',

        markers: {
          radius: 99,
        },
      },
      fill: {
        opacity: 1,
      },
    };

  const chartSelector = document.querySelectorAll('#chartTwo');

  if (chartSelector.length) {
    const chartTwo = new ApexCharts(
      document.querySelector('#chartTwo'),
      chartTwoOptions
    );
    chartTwo.render();
  }
};

export default chart02;
